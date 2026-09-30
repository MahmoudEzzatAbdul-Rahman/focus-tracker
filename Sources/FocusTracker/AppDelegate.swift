import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: FocusCoordinator?
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let coordinator = FocusCoordinator(settings: Settings())
        menuBar = MenuBarController(coordinator: coordinator)
        coordinator.start()
        self.coordinator = coordinator
    }
}
