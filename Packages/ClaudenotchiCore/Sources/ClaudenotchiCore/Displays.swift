import CoreGraphics

/// What the app needs to know about one connected display. A plain value so the choice of display can be
/// tested without any screen attached.
public struct ScreenInfo: Equatable, Sendable, Identifiable {
    /// Stable across launches and reconnects (the display's UUID).
    public var id: String
    public var name: String
    public var frame: CGRect
    public var safeAreaTop: CGFloat
    public var leftAreaWidth: CGFloat?
    public var rightAreaWidth: CGFloat?
    public var isMain: Bool

    public init(
        id: String, name: String, frame: CGRect, safeAreaTop: CGFloat,
        leftAreaWidth: CGFloat?, rightAreaWidth: CGFloat?, isMain: Bool
    ) {
        self.id = id
        self.name = name
        self.frame = frame
        self.safeAreaTop = safeAreaTop
        self.leftAreaWidth = leftAreaWidth
        self.rightAreaWidth = rightAreaWidth
        self.isMain = isMain
    }

    public var hasNotch: Bool { safeAreaTop > 0 && leftAreaWidth != nil && rightAreaWidth != nil }

    public var geometry: NotchGeometry { geometry(collapsedExtension: NotchGeometry.pillExtension) }

    public func geometry(collapsedExtension: CGFloat) -> NotchGeometry {
        NotchGeometry(
            screenFrame: frame, safeAreaTop: safeAreaTop, leftAreaWidth: leftAreaWidth, rightAreaWidth: rightAreaWidth,
            collapsedExtension: collapsedExtension
        )
    }

    /// The same screen treated as if it had no notch: the floating fallback pill. For trying that layout on a
    /// notch Mac.
    public var withoutNotch: ScreenInfo {
        var copy = self
        copy.safeAreaTop = 0
        copy.leftAreaWidth = nil
        copy.rightAreaWidth = nil
        return copy
    }
}

/// Which display the pill lives on.
public enum DisplayPreference: Equatable, Sendable {
    /// The screen with a notch if there is one, otherwise the main screen.
    case automatic
    case main
    case display(id: String)

    public init(storedValue: String) {
        switch storedValue {
        case "main": self = .main
        case let value where value.hasPrefix("display:") && value.count > "display:".count:
            self = .display(id: String(value.dropFirst("display:".count)))
        default: self = .automatic
        }
    }

    public var storedValue: String {
        switch self {
        case .automatic: "auto"
        case .main: "main"
        case .display(let id): "display:\(id)"
        }
    }
}

public enum DisplayChooser {
    /// Picks the screen for `preference`. A display that is no longer connected falls back to automatic, so
    /// unplugging a monitor never leaves the pill without a home.
    public static func choose(_ preference: DisplayPreference, from screens: [ScreenInfo]) -> ScreenInfo? {
        guard !screens.isEmpty else { return nil }
        switch preference {
        case .display(let id):
            if let match = screens.first(where: { $0.id == id }) { return match }
        case .main:
            if let main = screens.first(where: \.isMain) { return main }
        case .automatic:
            break
        }
        return screens.first(where: \.hasNotch) ?? screens.first(where: \.isMain) ?? screens.first
    }
}
