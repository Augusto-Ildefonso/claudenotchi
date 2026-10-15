import SwiftUI

@main
struct ClaudenotchiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(AppSettings.hoverDelayKey) private var hoverDelay = AppSettings.defaultHoverDelay
    @AppStorage(AppSettings.mascotSizeKey) private var mascotSize = AppSettings.defaultMascotSize
    @AppStorage(AppSettings.soundsEnabledKey) private var soundsEnabled = true

    var body: some Scene {
        MenuBarExtra("Claudenotchi", systemImage: "pawprint.fill") {
            Picker("Expand on hover", selection: $hoverDelay) {
                ForEach(AppSettings.hoverDelayOptions, id: \.seconds) { option in
                    Text(option.label).tag(option.seconds)
                }
            }
            Picker("Mascot size", selection: $mascotSize) {
                ForEach(AppSettings.mascotSizeOptions, id: \.points) { option in
                    Text(option.label).tag(option.points)
                }
            }
            Toggle("Play sounds", isOn: $soundsEnabled)
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
