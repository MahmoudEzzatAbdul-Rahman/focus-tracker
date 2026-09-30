@preconcurrency import AVFoundation
import AppKit
import ApplicationServices
import GazeCore
import OSLog
import QuartzCore

/// Wires the pipeline together: camera → features → gaze point → target window → highlight,
/// and focuses the target when the hotkey is tapped.
@MainActor
final class FocusCoordinator {
    let settings: Settings

    private(set) var calibration: CalibrationRecord?
    private(set) var target: WindowInfo?
    private(set) var isCameraAuthorized = false
    var isCalibrating: Bool { calibrationController != nil }
    var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }
    var isFaceDetected: Bool { CACurrentMediaTime() - latestFeaturesTime < featureMaxAge }

    private let camera = CameraFeed()
    private let locator = WindowLocator()
    private let focuser = WindowFocuser()
    private let hotkey = HotkeyMonitor()
    private let overlay = HighlightOverlay()
    private var debugWindow: DebugWindowController?
    private var calibrationController: CalibrationController?

    private var filter = PointFilter()
    private var selector = TargetSelector()
    private var dwellTrigger = DwellTrigger(delay: 0.8)
    private var latestFeatures: GazeFeatures?
    private var latestFeaturesTime: TimeInterval = -.infinity
    private var gazePoint: CGPoint?
    private var windows: [WindowInfo] = []
    private var windowsRefreshedAt: TimeInterval = -.infinity
    private var tickTimer: Timer?
    private var trustTimer: Timer?

    /// Features older than this count as "no face".
    private let featureMaxAge: TimeInterval = 0.3
    private let windowRefreshInterval: TimeInterval = 0.25

    init(settings: Settings) {
        self.settings = settings
    }

    func start() {
        calibration = CalibrationStore.load()

        let extractor = FaceFeatureExtractor()
        camera.onFrame = { [weak self] pixelBuffer in
            let features = extractor.extract(from: pixelBuffer)
            let time = CACurrentMediaTime()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.ingest(features, at: time) }
            }
        }

        hotkey.onTap = { [weak self] in self?.focusTarget() }
        requestAccessibility()
        requestCamera()

        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    // MARK: Actions

    func setEnabled(_ enabled: Bool) {
        settings.isEnabled = enabled
        updateCameraState()
    }

    func setUsesMouseAsGaze(_ usesMouse: Bool) {
        settings.usesMouseAsGaze = usesMouse
        updateCameraState()
    }

    func setFocusMode(_ mode: FocusMode) {
        settings.focusMode = mode
        dwellTrigger.reset()
    }

    func setDwellDelay(_ delay: TimeInterval) {
        settings.dwellDelay = delay
    }

    func selectCamera(id: String) {
        settings.cameraID = id
        if isCameraAuthorized { camera.start(deviceID: id) }
    }

    func startCalibration() {
        guard calibrationController == nil else { return }
        guard isCameraAuthorized else {
            openPrivacySettings(anchor: "Privacy_Camera")
            return
        }

        camera.start(deviceID: settings.cameraID)
        overlay.hide()
        let controller = CalibrationController()
        controller.onFinish = { [weak self] record in
            guard let self else { return }
            calibrationController = nil
            if let record {
                calibration = record
                CalibrationStore.save(record)
                filter.reset()
            }
            updateCameraState()
        }
        calibrationController = controller
        controller.start()
    }

    func showDebugWindow() {
        if debugWindow == nil { debugWindow = DebugWindowController(session: camera.session) }
        debugWindow?.show()
    }

    func openPrivacySettings(anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Pipeline

    private func ingest(_ features: GazeFeatures?, at time: TimeInterval) {
        guard let features else { return }
        latestFeatures = features
        latestFeaturesTime = time
        calibrationController?.ingest(features)
    }

    private func tick() {
        let now = CACurrentMediaTime()
        defer { updateDebugWindow() }

        guard settings.isEnabled, calibrationController == nil else {
            target = nil
            gazePoint = nil
            dwellTrigger.reset()
            overlay.hide()
            return
        }

        if now - windowsRefreshedAt > windowRefreshInterval {
            windows = locator.windows()
            windowsRefreshedAt = now
        }
        gazePoint = currentGazePoint(now: now)
        target = selector.update(point: gazePoint, windows: windows, now: now)
        overlay.show(target: target?.frame, gaze: settings.showsGazeDot ? gazePoint : nil)

        if settings.focusMode == .dwell {
            dwellTrigger.delay = settings.dwellDelay
            if dwellTrigger.update(targetID: target?.id, now: now) != nil, let target, !isFocused(target) {
                focus(target, beepOnFailure: false)
            }
        }
    }

    /// Whether `window` is already the frontmost window of the active app.
    private func isFocused(_ window: WindowInfo) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == window.pid else { return false }
        return windows.first { $0.pid == window.pid }?.id == window.id
    }

    private func currentGazePoint(now: TimeInterval) -> CGPoint? {
        if settings.usesMouseAsGaze {
            return CGEvent(source: nil)?.location
        }
        guard let model = calibration?.model, let latestFeatures, now - latestFeaturesTime < featureMaxAge else {
            filter.reset()
            return nil
        }
        // Filter on the frame's own timestamp: ticks between frames then leave the filter untouched.
        let smoothed = filter.filter(model.predict(latestFeatures), at: latestFeaturesTime)
        return smoothed.clamped(to: ScreenGeometry.mainDisplayBounds)
    }

    private func focusTarget() {
        guard settings.isEnabled, calibrationController == nil else { return }
        guard let target else {
            NSSound.beep()
            return
        }
        focus(target, beepOnFailure: true)
    }

    private func focus(_ window: WindowInfo, beepOnFailure: Bool) {
        if !focuser.focus(window) {
            Logger.focus.error("Could not focus \(window.ownerName, privacy: .public)")
            if beepOnFailure { NSSound.beep() }
        }
        windowsRefreshedAt = -.infinity
    }

    // MARK: Permissions and camera

    private func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            hotkey.start()
            return
        }
        // Global key monitors registered before trust is granted never receive events,
        // so wait for the grant and register then.
        trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, AXIsProcessTrusted() else { return }
                self.trustTimer?.invalidate()
                self.trustTimer = nil
                self.hotkey.start()
                Logger.app.info("Accessibility access granted")
            }
        }
    }

    private func requestCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isCameraAuthorized = true
            updateCameraState()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self.isCameraAuthorized = granted
                        self.updateCameraState()
                    }
                }
            }
        default:
            Logger.camera.error("Camera access denied")
        }
    }

    /// Runs the camera only while it is actually needed, so the camera light means "tracking".
    private func updateCameraState() {
        guard isCameraAuthorized else { return }
        let needed = isCalibrating || (settings.isEnabled && !settings.usesMouseAsGaze)
        if needed {
            camera.start(deviceID: settings.cameraID)
        } else {
            camera.stop()
            latestFeatures = nil
            latestFeaturesTime = -.infinity
        }
    }

    // MARK: Debug

    private func updateDebugWindow() {
        guard let debugWindow, debugWindow.isVisible else { return }
        var lines: [String] = []
        if let f = latestFeatures, isFaceDetected {
            lines.append(String(format: "yaw %+.3f  pitch %+.3f  roll %+.3f", f.yaw, f.pitch, f.roll))
            lines.append(String(format: "pupil x %+.2f  y %+.2f", f.pupilX, f.pupilY))
            lines.append(String(format: "face  x %.2f  y %.2f  size %.2f", f.faceX, f.faceY, f.faceSize))
        } else {
            lines.append("No face detected")
        }
        if let gazePoint {
            lines.append(String(format: "gaze  (%.0f, %.0f)", gazePoint.x, gazePoint.y))
        }
        lines.append("target \(target?.ownerName ?? "—")")
        if let calibration {
            lines.append(String(format: "calibration error %.0f pt", calibration.meanError))
        } else {
            lines.append("not calibrated")
        }
        debugWindow.update(text: lines.joined(separator: "\n"))
    }
}
