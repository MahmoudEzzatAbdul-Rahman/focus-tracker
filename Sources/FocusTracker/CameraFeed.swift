@preconcurrency import AVFoundation
import OSLog

/// Streams webcam frames on a background queue.
///
/// `onFrame` must be set before ``start(deviceID:)``; it is called on the frame queue.
final class CameraFeed: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    var onFrame: (@Sendable (CVPixelBuffer) -> Void)?

    private let sessionQueue = DispatchQueue(label: "io.local.focustracker.camera.session")
    private let frameQueue = DispatchQueue(label: "io.local.focustracker.camera.frames")
    private let output = AVCaptureVideoDataOutput()

    /// Cameras that can be selected, external ones first.
    static func availableDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    /// Starts (or restarts) capture from the given camera.
    ///
    /// - Parameter deviceID: `AVCaptureDevice.uniqueID` to use; falls back to the first
    ///   available camera, preferring external ones, when `nil` or not connected.
    func start(deviceID: String?) {
        sessionQueue.async { [self] in
            let devices = Self.availableDevices()
            guard let device = devices.first(where: { $0.uniqueID == deviceID }) ?? devices.first else {
                Logger.camera.error("No camera available")
                return
            }
            let currentID = session.inputs.compactMap { ($0 as? AVCaptureDeviceInput)?.device.uniqueID }.first
            if session.isRunning, currentID == device.uniqueID { return }

            session.beginConfiguration()
            session.inputs.forEach(session.removeInput)
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(input) { session.addInput(input) }
            } catch {
                Logger.camera.error("Could not open \(device.localizedName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
            if session.outputs.isEmpty {
                output.alwaysDiscardsLateVideoFrames = true
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
                output.setSampleBufferDelegate(self, queue: frameQueue)
                if session.canAddOutput(output) { session.addOutput(output) }
            }
            // 720p roughly doubles the pixels across each eye compared to VGA, which steadies the pupil offset.
            if let preset = [AVCaptureSession.Preset.hd1280x720, .vga640x480].first(where: session.canSetSessionPreset) {
                session.sessionPreset = preset
            }
            session.commitConfiguration()

            if !session.isRunning { session.startRunning() }
            Logger.camera.info("Capturing from \(device.localizedName, privacy: .public)")
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pixelBuffer)
    }
}
