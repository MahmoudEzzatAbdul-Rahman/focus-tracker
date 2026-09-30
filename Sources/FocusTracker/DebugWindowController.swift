@preconcurrency import AVFoundation
import AppKit

/// A small window with the live camera preview and the raw tracking values,
/// for positioning the camera and checking that landmarks are detected.
@MainActor
final class DebugWindowController {
    private let window: NSWindow
    private let label = NSTextField(labelWithString: "")

    init(session: AVCaptureSession) {
        window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 480, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "FocusTracker Debug"
        window.isReleasedWhenClosed = false
        window.level = .floating

        let preview = NSView(frame: CGRect(x: 0, y: 140, width: 480, height: 360))
        preview.wantsLayer = true
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = preview.bounds
        previewLayer.videoGravity = .resizeAspect
        if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        preview.layer?.addSublayer(previewLayer)

        label.frame = CGRect(x: 12, y: 8, width: 456, height: 124)
        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        label.maximumNumberOfLines = 0

        let content = NSView(frame: CGRect(x: 0, y: 0, width: 480, height: 500))
        content.addSubview(preview)
        content.addSubview(label)
        window.contentView = content
        window.center()
    }

    var isVisible: Bool { window.isVisible }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func update(text: String) {
        guard label.stringValue != text else { return }
        label.stringValue = text
    }
}
