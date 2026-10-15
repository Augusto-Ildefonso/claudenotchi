import ClaudenotchiCore
import SwiftUI

@main
struct ClaudenotchiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(AppSettings.hoverDelayKey) private var hoverDelay = AppSettings.defaultHoverDelay
    @AppStorage(AppSettings.mascotSizeKey) private var mascotSize = AppSettings.defaultMascotSize
    @AppStorage(AppSettings.displayPreferenceKey) private var displayPreference = "auto"
    @AppStorage(AppSettings.soundsEnabledKey) private var soundsEnabled = true
    @State private var displays = DisplayList()
    @State private var loginItem = LaunchAtLogin()

    var body: some Scene {
        MenuBarExtra {
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
            Picker("Show on", selection: $displayPreference) {
                Text("Automatic").tag(DisplayPreference.automatic.storedValue)
                Text("Main display").tag(DisplayPreference.main.storedValue)
                Divider()
                ForEach(displays.screens) { screen in
                    Text(screen.hasNotch ? "\(screen.name) (notch)" : screen.name)
                        .tag(DisplayPreference.display(id: screen.id).storedValue)
                }
            }
            Toggle("Play sounds", isOn: $soundsEnabled)
            Toggle("Open at login", isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.set($0) }))
            if loginItem.needsApproval {
                Text("Approve Claudenotchi in System Settings > Login Items")
            }
            if let failure = loginItem.failure {
                Text("Open at login: \(failure)")
            }
            Divider()
            HookMenuSection(setup: appDelegate.hookSetup)
            Divider()
            Button("Quit Claudenotchi") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            // The mascot as a template image: macOS tints it for light, dark and the selected state.
            Image("MenuBarIcon")
                .accessibilityLabel("Claudenotchi")
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
