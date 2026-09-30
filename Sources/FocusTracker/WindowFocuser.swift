import AppKit
import ApplicationServices
import GazeCore
import OSLog

/// Gives keyboard focus to a specific window of another app via the Accessibility API.
///
/// The AX route is used because macOS 14+ cooperative activation ignores
/// `NSRunningApplication.activate()` calls coming from a background app.
@MainActor
struct WindowFocuser {
    /// How far (in points, summed over origin and size) an AX window may differ from the target.
    private let frameTolerance: CGFloat = 40

    /// Brings `target` to the front and makes its app frontmost.
    ///
    /// - Parameter target: The window to focus.
    /// - Returns: `true` when the app was activated.
    func focus(_ target: WindowInfo) -> Bool {
        let app = AXUIElementCreateApplication(target.pid)

        let activated = AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, true as CFBoolean) == .success
        if let window = matchingWindow(in: app, frame: target.frame) {
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, true as CFBoolean)
        } else {
            Logger.focus.info("No AX window of \(target.ownerName, privacy: .public) matches \(String(describing: target.frame), privacy: .public)")
        }

        if activated { return true }

        Logger.focus.info("AX activation of \(target.ownerName, privacy: .public) failed, falling back to NSRunningApplication")
        return NSRunningApplication(processIdentifier: target.pid)?.activate() ?? false
    }

    private func matchingWindow(in app: AXUIElement, frame: CGRect) -> AXUIElement? {
        guard let windows = copyAttribute(app, kAXWindowsAttribute) as? [AXUIElement] else { return nil }

        return windows
            .compactMap { window -> (AXUIElement, CGFloat)? in
                guard let windowFrame = self.frame(of: window) else { return nil }
                let difference = abs(windowFrame.minX - frame.minX) + abs(windowFrame.minY - frame.minY)
                    + abs(windowFrame.width - frame.width) + abs(windowFrame.height - frame.height)
                return (window, difference)
            }
            .filter { $0.1 <= frameTolerance }
            .min { $0.1 < $1.1 }?
            .0
    }

    /// AX window frame in global Quartz coordinates (same space as `CGWindowList`).
    private func frame(of window: AXUIElement) -> CGRect? {
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard
            let position = copyAttribute(window, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
            let dimensions = copyAttribute(window, kAXSizeAttribute), CFGetTypeID(dimensions) == AXValueGetTypeID(),
            AXValueGetValue(position as! AXValue, .cgPoint, &origin),
            AXValueGetValue(dimensions as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private func copyAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }
}
