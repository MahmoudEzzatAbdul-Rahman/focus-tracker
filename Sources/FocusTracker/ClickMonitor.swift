import AppKit

/// Reports left mouse clicks anywhere in other apps, for learning where the user looks.
///
/// Only the click position is reported. Clicks in FocusTracker's own menu and windows are not,
/// since they say nothing reliable about the gaze. ``start()`` is safe to call again.
@MainActor
final class ClickMonitor {
    /// Called with the click position in global Quartz coordinates (top-left origin).
    var onClick: ((CGPoint) -> Void)?

    private var monitor: Any?

    func start() {
        stop()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            let location = event.cgEvent?.location ?? CGEvent(source: nil)?.location
            MainActor.assumeIsolated {
                if let location { self?.onClick?(location) }
            }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
