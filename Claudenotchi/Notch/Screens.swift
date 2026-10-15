import AppKit
import ClaudenotchiCore
import Observation

extension ScreenInfo {
    init(_ screen: NSScreen, isMain: Bool) {
        self.init(
            id: Self.stableID(of: screen),
            name: screen.localizedName,
            frame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            leftAreaWidth: screen.auxiliaryTopLeftArea?.width,
            rightAreaWidth: screen.auxiliaryTopRightArea?.width,
            isMain: isMain
        )
    }

    /// The display's UUID: the same after a reboot or after unplugging and reconnecting the monitor.
    private static func stableID(of screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(number.uint32Value))?.takeRetainedValue(),
              let string = CFUUIDCreateString(nil, uuid) as String? else {
            return screen.localizedName
        }
        return string
    }

    /// All connected displays. The first one is the one with the menu bar, which macOS calls the main display.
    /// `-forceNotchless YES` on the command line treats every display as having no notch, to try the fallback
    /// pill on a notch Mac.
    static func connected() -> [ScreenInfo] {
        let forceNotchless = UserDefaults.standard.bool(forKey: AppSettings.forceNotchlessKey)
        return NSScreen.screens.enumerated().map { index, screen in
            let info = ScreenInfo(screen, isMain: index == 0)
            return forceNotchless ? info.withoutNotch : info
        }
    }
}

/// The connected displays, kept current for the menu.
@Observable
final class DisplayList {
    private(set) var screens = ScreenInfo.connected()

    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screens = ScreenInfo.connected() }
        }
    }
}
