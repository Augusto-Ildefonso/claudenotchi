import SwiftUI

@main
struct ClaudenotchiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(AppSettings.hoverDelayKey) private var hoverDelay = AppSettings.defaultHoverDelay

    var body: some Scene {
        MenuBarExtra("Claudenotchi", systemImage: "pawprint.fill") {
            Picker("Expand on hover", selection: $hoverDelay) {
                ForEach(AppSettings.hoverDelayOptions, id: \.seconds) { option in
                    Text(option.label).tag(option.seconds)
                }
            }
            Divider()
            HookMenuSection(setup: appDelegate.hookSetup)
            Divider()
            Button("Quit Claudenotchi") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}

/// Status line and install/uninstall button for the Claude Code hooks.
private struct HookMenuSection: View {
    let setup: HookSetup

    var body: some View {
        switch setup.status {
        case .installed:
            Text("Claude Code hooks: installed")
            Button("Uninstall Claude Code hooks") { setup.uninstall() }
        case .notInstalled:
            Text("Claude Code hooks: not installed")
            Button("Install Claude Code hooks") { setup.install() }
        case .failed(let message):
            Text("Claude Code hooks: \(message)")
            Button("Try installing again") { setup.install() }
        }
    }
}
