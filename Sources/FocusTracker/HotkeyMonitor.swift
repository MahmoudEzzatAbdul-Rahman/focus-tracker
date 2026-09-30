import AppKit
import Carbon.HIToolbox

/// Detects a lone tap of the left Control key anywhere in the system.
///
/// A tap is a press and release within ``maximumTapDuration`` with no other key, modifier
/// or mouse click in between, so ⌃-shortcuts and ⌃-clicks never trigger it. Caps Lock is ignored.
/// Global monitoring needs Accessibility permission; ``start()`` is safe to call again after it is granted.
@MainActor
final class HotkeyMonitor {
    var onTap: (() -> Void)?

    private let triggerKeyCode = UInt16(kVK_Control)
    private let triggerModifier: NSEvent.ModifierFlags = .control
    private let maximumTapDuration: TimeInterval = 0.35
    private var monitors: [Any] = []
    private var pressedAt: TimeInterval?
    private var interrupted = false

    func start() {
        stop()
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        pressedAt = nil
    }

    private func handle(_ event: NSEvent) {
        guard event.type == .flagsChanged, event.keyCode == triggerKeyCode else {
            interrupted = true
            return
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
        if modifiers.contains(triggerModifier) {
            pressedAt = event.timestamp
            interrupted = modifiers != triggerModifier
        } else if let pressedAt {
            self.pressedAt = nil
            if !interrupted, event.timestamp - pressedAt <= maximumTapDuration {
                onTap?()
            }
        }
    }
}
