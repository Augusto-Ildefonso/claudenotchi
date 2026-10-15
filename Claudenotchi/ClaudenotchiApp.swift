import SwiftUI

@main
struct ClaudenotchiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Claudenotchi", systemImage: "pawprint.fill") {
            Button("Quit Claudenotchi") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
