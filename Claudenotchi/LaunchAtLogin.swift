import Observation
import OSLog
import ServiceManagement

/// "Open at login" through the system's login-item service. macOS shows its own notification the first time.
@Observable
final class LaunchAtLogin {
    private(set) var status = SMAppService.mainApp.status
    private(set) var failure: String?

    @ObservationIgnored private let log = Logger(subsystem: "dev.claudenotchi.Claudenotchi", category: "login")

    var isEnabled: Bool { status == .enabled }

    /// The user turned it on in System Settings > Login Items but still has to approve it there.
    var needsApproval: Bool { status == .requiresApproval }

    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            failure = nil
        } catch {
            log.error("Login item change failed: \(String(describing: error))")
            failure = error.localizedDescription
        }
        status = SMAppService.mainApp.status
    }
}
