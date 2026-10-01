import AppKit

/// The menu bar item: status, toggles and actions. The menu is rebuilt every time it opens.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let coordinator: FocusCoordinator
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    init(coordinator: FocusCoordinator) {
        self.coordinator = coordinator
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "FocusTracker")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let settings = coordinator.settings

        menu.addItem(disabled(statusLine))
        if !settings.usesMouseAsGaze {
            menu.addItem(disabled(accuracyLine))
        }
        if !coordinator.isAccessibilityTrusted {
            menu.addItem(action("Grant Accessibility Access…") { [coordinator] in
                coordinator.openPrivacySettings(anchor: "Privacy_Accessibility")
            })
        }
        if !coordinator.isCameraAuthorized {
            menu.addItem(action("Grant Camera Access…") { [coordinator] in
                coordinator.openPrivacySettings(anchor: "Privacy_Camera")
            })
        }
        menu.addItem(.separator())

        menu.addItem(toggle("Enabled", isOn: settings.isEnabled) { [coordinator] in
            coordinator.setEnabled(!settings.isEnabled)
        })
        menu.addItem(focusModeMenu())
        menu.addItem(toggle("Learn from Clicks", isOn: settings.learnsFromClicks) { [coordinator] in
            coordinator.setLearnsFromClicks(!settings.learnsFromClicks)
        })
        menu.addItem(action("Quick Calibrate…") { [coordinator] in
            coordinator.startCalibration()
        })
        menu.addItem(action("Reset Learning") { [coordinator] in
            coordinator.resetLearning()
        })
        menu.addItem(cameraMenu())
        menu.addItem(.separator())

        menu.addItem(toggle("Show Gaze Dot", isOn: settings.showsGazeDot) {
            settings.showsGazeDot.toggle()
        })
        menu.addItem(toggle("Use Mouse as Gaze", isOn: settings.usesMouseAsGaze) { [coordinator] in
            coordinator.setUsesMouseAsGaze(!settings.usesMouseAsGaze)
        })
        menu.addItem(action("Show Debug Window") { [coordinator] in
            coordinator.showDebugWindow()
        })
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit FocusTracker", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private var statusLine: String {
        let settings = coordinator.settings
        if !settings.isEnabled { return "Paused" }
        if coordinator.isCalibrating { return "Calibrating…" }
        if !settings.usesMouseAsGaze, !coordinator.isFaceDetected { return "No face detected" }
        if let target = coordinator.target {
            return settings.focusMode == .hotkey
                ? "Looking at \(target.ownerName) — tap left ⌃ to focus"
                : "Looking at \(target.ownerName)"
        }
        return "Tracking"
    }

    private var accuracyLine: String {
        let learning = coordinator.learning
        if learning.samples.isEmpty { return "Using default gaze model" }
        if let error = learning.typicalError {
            return String(format: "Accuracy ≈ %.0f pt (%d samples)", error, learning.samples.count)
        }
        return "Learning… (\(learning.samples.count) samples)"
    }

    private func focusModeMenu() -> NSMenuItem {
        let settings = coordinator.settings
        let item = NSMenuItem(title: "Focus Mode", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.addItem(toggle("Tap Left ⌃", isOn: settings.focusMode == .hotkey) { [coordinator] in
            coordinator.setFocusMode(.hotkey)
        })
        submenu.addItem(toggle("Look (Dwell)", isOn: settings.focusMode == .dwell) { [coordinator] in
            coordinator.setFocusMode(.dwell)
        })
        submenu.addItem(.separator())
        submenu.addItem(disabled("Dwell Time"))
        for delay in Settings.dwellDelayChoices {
            let choice = toggle(String(format: "%.1f s", delay), isOn: settings.dwellDelay == delay) { [coordinator] in
                coordinator.setDwellDelay(delay)
            }
            choice.indentationLevel = 1
            choice.isEnabled = settings.focusMode == .dwell
            submenu.addItem(choice)
        }
        item.submenu = submenu
        return item
    }

    private func cameraMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Camera", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let devices = CameraFeed.availableDevices()
        let selectedID = coordinator.settings.cameraID ?? devices.first?.uniqueID
        for device in devices {
            let id = device.uniqueID
            submenu.addItem(toggle(device.localizedName, isOn: id == selectedID) { [coordinator] in
                coordinator.selectCamera(id: id)
            })
        }
        if devices.isEmpty { submenu.addItem(disabled("No cameras found")) }
        item.submenu = submenu
        return item
    }

    // MARK: Item helpers

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ handler: @escaping @MainActor () -> Void) -> NSMenuItem {
        ClosureMenuItem(title: title, handler: handler)
    }

    private func toggle(_ title: String, isOn: Bool, _ handler: @escaping @MainActor () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, handler: handler)
        item.state = isOn ? .on : .off
        return item
    }
}

/// A menu item that runs a closure instead of sending an action through the responder chain.
@MainActor
private final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func run() {
        handler()
    }
}
