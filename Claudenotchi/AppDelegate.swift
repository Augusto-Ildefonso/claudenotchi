import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = CompanionModel()
    let hookSetup = HookSetup()
    private var notchController: NotchWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard model.start() else {
            NSApplication.shared.terminate(nil) // another copy is running; do not fight it for the socket
            return
        }
        hookSetup.start()
        let controller = NotchWindowController(model: model)
        controller.show()
        notchController = controller
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }
}
