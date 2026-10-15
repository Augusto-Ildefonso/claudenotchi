import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = CompanionModel()
    private var notchController: NotchWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
        let controller = NotchWindowController(model: model)
        controller.show()
        notchController = controller
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }
}
