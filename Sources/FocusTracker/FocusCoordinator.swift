@preconcurrency import AVFoundation
import AppKit
import ApplicationServices
import GazeCore
import OSLog
import QuartzCore

/// Wires the pipeline together: camera → features → gaze point → target window → highlight,
/// focuses the target when the hotkey is tapped, and learns from the user's clicks.
@MainActor
final class FocusCoordinator {
    let settings: Settings

    /// What has been learned about the user's gaze; starts from population defaults.
    private(set) var learning = SelfCalibration()
    private(set) var target: WindowInfo?
    private(set) var isCameraAuthorized = false
    var isCalibrating: Bool { calibrationController != nil }
    var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }
    var isFaceDetected: Bool { CACurrentMediaTime() - latestFeaturesTime < featureMaxAge }

    private let camera = CameraFeed()
    private let locator = WindowLocator()
    private let focuser = WindowFocuser()
    private let hotkey = HotkeyMonitor()
    private let clicks = ClickMonitor()
    private let overlay = HighlightOverlay()
    private var debugWindow: DebugWindowController?
    private var calibrationController: CalibrationController?

    private var geometry = ScreenGeometry.gazeGeometry
    private var stabilizer = GazeStabilizer(radius: 0)
    private var blinkDetector = BlinkDetector()
    private var medianFilter = FeatureMedianFilter()
    private var selector = TargetSelector()
    private var dwellTrigger = DwellTrigger(delay: 0.8)
    private var latestFeatures: GazeFeatures?
    private var latestFeaturesTime: TimeInterval = -.infinity
    /// Recent non-blink features, for averaging over the moment of a click.
    private var recentFeatures: [(time: TimeInterval, features: GazeFeatures)] = []
    private var gazePoint: CGPoint?
    private var windows: [WindowInfo] = []
    private var windowsRefreshedAt: TimeInterval = -.infinity
    private var tickTimer: Timer?
    private var trustTimer: Timer?
    private var unsavedSamples = 0

    /// Features older than this count as "no face".
    private let featureMaxAge: TimeInterval = 0.3
    private let windowRefreshInterval: TimeInterval = 0.25
    /// Features from this long before a click are averaged into its sample.
    private let clickFeatureWindow: TimeInterval = 0.15
    /// The profile is saved after this many new samples (and on quit).
    private let samplesPerSave = 10
    /// Fixation radius as a fraction of the screen diagonal.
    private let fixationRadiusFraction = 0.035

    init(settings: Settings) {
        self.settings = settings
    }

    func start() {
        learning = GazeProfileStore.load() ?? SelfCalibration()
        refreshGeometry()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshGeometry() }
        }

        let extractor = FaceFeatureExtractor()
        camera.onFrame = { [weak self] pixelBuffer in
            let features = extractor.extract(from: pixelBuffer)
            let time = CACurrentMediaTime()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.ingest(features, at: time) }
            }
        }

        hotkey.onTap = { [weak self] in self?.focusTarget() }
        clicks.onClick = { [weak self] location in self?.learn(fromClickAt: location) }
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

    func setLearnsFromClicks(_ learns: Bool) {
        settings.learnsFromClicks = learns
    }

    /// Forgets everything learned from clicks and calibration, going back to the defaults.
    func resetLearning() {
        learning.reset()
        stabilizer.reset()
        saveProfile()
    }

    func saveProfile() {
        GazeProfileStore.save(learning)
        unsavedSamples = 0
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
        let controller = CalibrationController(geometry: geometry) { [learning, geometry] samples in
            learning.fitted(adding: samples, geometry: geometry)
        }
        controller.onFinish = { [weak self] result in
            guard let self else { return }
            calibrationController = nil
            if let result {
                learning.add(contentsOf: result.samples, geometry: geometry)
                learning.record(errors: result.validationErrors)
                saveProfile()
                stabilizer.reset()
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
        // Blink frames are dropped: the pupil landmarks jump while the eyes are closed.
        guard let features, !blinkDetector.isBlinking(openness: features.eyeOpenness) else { return }
        let smoothed = medianFilter.filter(features)
        latestFeatures = smoothed
        latestFeaturesTime = time
        recentFeatures.append((time, smoothed))
        recentFeatures.removeAll { time - $0.time > 1 }
        calibrationController?.ingest(smoothed)
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
        guard let latestFeatures, now - latestFeaturesTime < featureMaxAge else {
            stabilizer.reset()
            medianFilter.reset()
            return nil
        }
        guard let predicted = learning.model.predict(latestFeatures, geometry: geometry) else { return nil }
        // Stabilize on the frame's own timestamp: ticks between frames then leave the stabilizer untouched.
        let stabilized = stabilizer.update(predicted.clamped(to: geometry.screenFrame), at: latestFeaturesTime)
        return stabilized.clamped(to: geometry.screenFrame)
    }

    private func refreshGeometry() {
        geometry = ScreenGeometry.gazeGeometry
        let diagonal = Double(hypot(geometry.screenFrame.width, geometry.screenFrame.height))
        stabilizer = GazeStabilizer(radius: diagonal * fixationRadiusFraction)
    }

    /// Treats a click as a calibration sample: the user was almost certainly looking at it.
    private func learn(fromClickAt location: CGPoint) {
        guard
            settings.isEnabled, settings.learnsFromClicks, !settings.usesMouseAsGaze, calibrationController == nil,
            geometry.screenFrame.contains(location)
        else { return }
        let now = CACurrentMediaTime()
        let recent = recentFeatures.filter { now - $0.time <= clickFeatureWindow }.map(\.features)
        guard let features = GazeFeatures.mean(of: recent) else { return }

        let outcome = learning.add(click: GazeSample(features: features, screenPoint: location), geometry: geometry)
        switch outcome {
        case .accepted(let error):
            Logger.calibration.debug("Learned from click, error \(error, format: .fixed(precision: 0)) pt")
            unsavedSamples += 1
            if unsavedSamples >= samplesPerSave { saveProfile() }
        case .rejected(let error):
            Logger.calibration.debug("Ignored click \(error, format: .fixed(precision: 0)) pt from the gaze")
        case .unusable:
            break
        }
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
            clicks.start()
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
                self.clicks.start()
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
            recentFeatures.removeAll()
        }
    }

    // MARK: Debug

    private func updateDebugWindow() {
        guard let debugWindow, debugWindow.isVisible else { return }
        var lines: [String] = []
        if let f = latestFeatures, isFaceDetected {
            lines.append(String(format: "yaw %+.3f  pitch %+.3f  roll %+.3f  eyes open %.2f", f.yaw, f.pitch, f.roll, f.eyeOpenness))
            lines.append(String(format: "pupil x %+.2f  y %+.2f", f.pupilX, f.pupilY))
            if let head = geometry.headPosition(f) {
                let angles = learning.model.angles(f, head: head)
                lines.append(String(format: "head  %+.0f cm right  %+.0f cm below camera  %.0f cm away",
                                    head.x / 10, head.y / 10, head.distance / 10))
                lines.append(String(format: "gaze angle  %+.1f° right  %+.1f° down",
                                    angles.horizontal * 180 / .pi, angles.vertical * 180 / .pi))
            }
        } else {
            lines.append("No face detected")
        }
        if let gazePoint {
            lines.append(String(format: "gaze  (%.0f, %.0f)   target %@", gazePoint.x, gazePoint.y, target?.ownerName ?? "—"))
        } else {
            lines.append("target \(target?.ownerName ?? "—")")
        }
        if learning.samples.isEmpty {
            lines.append("using defaults — click around or Quick Calibrate")
        } else if let error = learning.typicalError {
            lines.append(String(format: "learned from %d samples, typical error %.0f pt", learning.samples.count, error))
        } else {
            lines.append("learned from \(learning.samples.count) samples")
        }
        debugWindow.update(text: lines.joined(separator: "\n"))
    }
}
