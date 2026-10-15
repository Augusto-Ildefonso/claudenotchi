import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = CompanionModel()
    let hookSetup = HookSetup()
    private var notchController: NotchWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
        hookSetup.start()
        let controller = NotchWindowController(model: model)
        controller.show()
        notchController = controller
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }
}
