import AppKit
import QuartzCore

/// A transparent, click-through layer over the main display that outlines the
/// targeted window and optionally shows the estimated gaze point.
@MainActor
final class HighlightOverlay {
    private let panel: NSPanel
    private let border = CAShapeLayer()
    private let dot = CALayer()
    private let dotDiameter: CGFloat = 16
    private var currentTarget: CGRect?
    private var currentGaze: CGPoint?

    init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let content = NSView()
        content.wantsLayer = true
        border.fillColor = nil
        border.strokeColor = NSColor.systemBlue.withAlphaComponent(0.85).cgColor
        border.lineWidth = 4
        dot.backgroundColor = NSColor.systemRed.withAlphaComponent(0.6).cgColor
        dot.cornerRadius = dotDiameter / 2
        dot.bounds = CGRect(x: 0, y: 0, width: dotDiameter, height: dotDiameter)
        content.layer?.addSublayer(border)
        content.layer?.addSublayer(dot)
        panel.contentView = content

        fitToScreen()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.fitToScreen() }
        }
    }

    /// Draws the highlight.
    ///
    /// - Parameters:
    ///   - target: Window frame to outline, in global Quartz coordinates, or `nil` for none.
    ///   - gaze: Gaze point to mark, in global Quartz coordinates, or `nil` for none.
    func show(target: CGRect?, gaze: CGPoint?) {
        guard target != currentTarget || gaze != currentGaze else { return }
        currentTarget = target
        currentGaze = gaze

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let target {
            let local = ScreenGeometry.cocoaRect(fromQuartz: target).insetBy(dx: 2, dy: 2)
            border.path = CGPath(roundedRect: local, cornerWidth: 10, cornerHeight: 10, transform: nil)
            border.isHidden = false
        } else {
            border.isHidden = true
        }
        if let gaze {
            dot.position = CGPoint(x: gaze.x, y: ScreenGeometry.mainDisplayBounds.height - gaze.y)
            dot.isHidden = false
        } else {
            dot.isHidden = true
        }
        CATransaction.commit()

        if target == nil && gaze == nil {
            panel.orderOut(nil)
        } else if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        show(target: nil, gaze: nil)
    }

    private func fitToScreen() {
        panel.setFrame(ScreenGeometry.cocoaRect(fromQuartz: ScreenGeometry.mainDisplayBounds), display: false)
    }
}
