import AppKit
import GazeCore
import OSLog

/// Runs the optional full-screen calibration: shows dots, collects ``GazeFeatures`` while the
/// user looks at each one, then measures the resulting model on separate validation dots.
///
/// Calibration gives the click learning a quick, evenly spread start. The samples it collects
/// are handed back rather than fitted here, so they join the clicks in one ``SelfCalibration``.
@MainActor
final class CalibrationController {
    enum Failure: Error {
        case faceNotDetected
    }

    struct Result {
        /// Samples from both the training and the validation dots.
        var samples: [GazeSample]
        /// Distance in points between predicted and actual position for each validation sample.
        var validationErrors: [Double]

        var meanError: Double {
            validationErrors.reduce(0, +) / Double(max(validationErrors.count, 1))
        }
    }

    /// Called once with the result, or `nil` when calibration was cancelled or failed.
    var onFinish: ((Result?) -> Void)?

    /// Where the dots go, as fractions of the screen size.
    private let trainingLayout: [CGPoint] =
        [0.06, 0.5, 0.94].flatMap { y in [0.06, 0.5, 0.94].map { x in CGPoint(x: x, y: y) } }
    private let validationLayout = [
        CGPoint(x: 0.25, y: 0.5), CGPoint(x: 0.75, y: 0.5), CGPoint(x: 0.5, y: 0.2), CGPoint(x: 0.5, y: 0.8),
    ]
    /// Time for the eyes to settle on a new dot before sampling starts.
    private let settleTime: Duration = .milliseconds(700)
    private let collectTime: Duration = .milliseconds(1000)
    /// Fewer frames than this for a dot means the face was lost.
    private let minimumFramesPerDot = 8
    /// Consecutive frames averaged into one sample, so a dot weighs about as much as a few clicks.
    private let framesPerSample = 6

    private let geometry: GazeGeometry
    /// Fits a model to the given samples on top of what has already been learned.
    private let fit: ([GazeSample]) -> GazeModel
    private let screenBounds: CGRect
    private let window: CalibrationWindow
    private let view: CalibrationView
    private var collectingAt: CGPoint?
    private var collected: [GazeFeatures] = []
    private var task: Task<Void, Never>?

    /// - Parameters:
    ///   - geometry: Physical setup, used to turn predictions into screen points.
    ///   - fit: Fits a model to the training samples on top of what has already been learned.
    init(geometry: GazeGeometry, fit: @escaping ([GazeSample]) -> GazeModel) {
        self.geometry = geometry
        self.fit = fit
        screenBounds = geometry.screenFrame
        view = CalibrationView()
        window = CalibrationWindow(
            contentRect: ScreenGeometry.cocoaRect(fromQuartz: screenBounds),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver + 1
        window.contentView = view
        window.isReleasedWhenClosed = false
        window.onCancel = { [weak self] in self?.cancel() }
    }

    func start() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        NSCursor.hide()
        task = Task { await run() }
    }

    func cancel() {
        task?.cancel()
    }

    /// Feeds features from the camera; only used while a dot is being sampled.
    func ingest(_ features: GazeFeatures) {
        guard collectingAt != nil else { return }
        collected.append(features)
    }

    private func run() async {
        var result: Result?
        do {
            view.message = "Look at each dot as it appears — sit as you normally do.\nPress Esc to cancel."
            try await Task.sleep(for: .seconds(2.5))
            view.message = nil

            let training = try await collect(at: trainingLayout.shuffled())
            let model = fit(training)

            let validation = try await collect(at: validationLayout)
            let errors = validation.map { sample in
                model.predict(sample.features, geometry: geometry).map { $0.distance(to: sample.screenPoint) }
                    ?? Double(hypot(screenBounds.width, screenBounds.height))
            }
            let finished = Result(samples: training + validation, validationErrors: errors)
            result = finished
            Logger.calibration.info("Calibrated with \(training.count) samples, mean error \(finished.meanError, format: .fixed(precision: 0)) pt")

            view.dot = nil
            view.message = String(format: "Calibration done — average error %.0f pt\nClicking around keeps improving it.", finished.meanError)
            try await Task.sleep(for: .seconds(2))
        } catch is CancellationError {
            result = nil
        } catch {
            Logger.calibration.error("Calibration failed: \(String(describing: error), privacy: .public)")
            view.dot = nil
            view.message = "Calibration failed: your face wasn't detected reliably.\nCheck the camera and lighting, then try again."
            try? await Task.sleep(for: .seconds(3))
        }
        finish(result)
    }

    /// Shows each dot in turn and turns the frames recorded while it was on screen into samples.
    private func collect(at layout: [CGPoint]) async throws -> [GazeSample] {
        var samples: [GazeSample] = []
        for fraction in layout {
            let point = CGPoint(
                x: screenBounds.minX + fraction.x * screenBounds.width,
                y: screenBounds.minY + fraction.y * screenBounds.height
            )
            view.dot = CalibrationView.Dot(center: point, isSampling: false)
            try await Task.sleep(for: settleTime)

            collected = []
            collectingAt = point
            view.dot = CalibrationView.Dot(center: point, isSampling: true)
            try await Task.sleep(for: collectTime)
            collectingAt = nil

            guard collected.count >= minimumFramesPerDot else { throw Failure.faceNotDetected }
            samples += stride(from: 0, to: collected.count, by: framesPerSample).compactMap { start in
                GazeFeatures.mean(of: Array(collected[start..<min(start + framesPerSample, collected.count)]))
                    .map { GazeSample(features: $0, screenPoint: point) }
            }
        }
        return samples
    }

    private func finish(_ result: Result?) {
        collectingAt = nil
        NSCursor.unhide()
        window.orderOut(nil)
        onFinish?(result)
        onFinish = nil
    }
}

/// Borderless windows can't become key by default; calibration needs key status for Esc.
private final class CalibrationWindow: NSWindow {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }
}

private final class CalibrationView: NSView {
    struct Dot: Equatable {
        /// Center in global Quartz coordinates.
        var center: CGPoint
        var isSampling: Bool
    }

    var dot: Dot? { didSet { needsDisplay = true } }
    var message: String? { didSet { needsDisplay = true } }

    // Quartz and view coordinates then share a top-left origin on the main display.
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.08, alpha: 1).setFill()
        bounds.fill()

        if let dot {
            let outer: CGFloat = 26
            let color: NSColor = dot.isSampling ? .systemGreen : .systemRed
            color.setFill()
            NSBezierPath(ovalIn: CGRect(x: dot.center.x - outer / 2, y: dot.center.y - outer / 2, width: outer, height: outer)).fill()
            NSColor.white.setFill()
            NSBezierPath(ovalIn: CGRect(x: dot.center.x - 3, y: dot.center.y - 3, width: 6, height: 6)).fill()
        }

        if let message {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 28, weight: .medium),
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph,
            ]
            let text = NSAttributedString(string: message, attributes: attributes)
            let size = text.boundingRect(with: CGSize(width: bounds.width * 0.7, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin).size
            text.draw(in: CGRect(x: (bounds.width - size.width) / 2, y: bounds.height * 0.4, width: size.width, height: size.height + 4))
        }
    }
}
