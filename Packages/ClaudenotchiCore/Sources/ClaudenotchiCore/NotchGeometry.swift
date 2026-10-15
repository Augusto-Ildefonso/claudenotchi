import CoreGraphics

/// How much of the pill is showing.
public enum PillPresentation: Equatable, Sendable {
    /// Just the mascot beside the notch.
    case collapsed
    /// Hover: mascot, status and project folder.
    case hover
    /// A permission prompt or other request for the user, with room for buttons.
    case attention
}

/// Where the pill sits on a screen. Pure value type so it can be unit tested without a display.
public struct NotchGeometry: Equatable, Sendable {
    /// How far the collapsed pill extends past each side of the notch, so the pill stays symmetric
    /// around the notch. The left side holds the mascot; the right side is reserved for status.
    public static let pillExtension: CGFloat = 56
    /// Size of the floating pill on screens without a notch.
    public static let fallbackSize = CGSize(width: 190, height: 32)
    /// Width of the hover-expanded panel.
    public static let expandedWidth: CGFloat = 420
    /// Height of the expanded content below the notch-height bar.
    public static let expandedContentHeight: CGFloat = 64
    /// Width of the attention panel (permission prompt with buttons).
    public static let attentionWidth: CGFloat = 460
    /// Height below the notch bar for a one-line request: padding, the mascot / text row, and the
    /// buttons. Kept tight on purpose; spare height shows as an empty black strip under the buttons.
    public static let attentionContentHeight: CGFloat = 98
    /// Extra height when the request text wraps to a second line.
    public static let attentionLineHeight: CGFloat = 15
    /// How much taller the button row is than the one-line hint that replaces it when there is nothing to
    /// approve (a question or a plan, which only the terminal can answer).
    public static let attentionButtonRowHeight: CGFloat = 17

    public let hasNotch: Bool
    /// Notch rectangle in global screen coordinates (origin bottom-left). Zero-sized when `hasNotch` is false.
    public let notchRect: CGRect
    public let screenFrame: CGRect

    /// - Parameters:
    ///   - screenFrame: `NSScreen.frame`
    ///   - safeAreaTop: `NSScreen.safeAreaInsets.top` (non-zero on notch displays)
    ///   - leftAreaWidth / rightAreaWidth: widths of `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`
    ///     (nil when the screen has no notch). Only widths are used, so the result does not depend on
    ///     whether those rects are in local or global coordinates.
    public init(screenFrame: CGRect, safeAreaTop: CGFloat, leftAreaWidth: CGFloat?, rightAreaWidth: CGFloat?) {
        self.screenFrame = screenFrame
        if safeAreaTop > 0, let left = leftAreaWidth, let right = rightAreaWidth {
            hasNotch = true
            notchRect = CGRect(
                x: screenFrame.minX + left,
                y: screenFrame.maxY - safeAreaTop,
                width: screenFrame.width - left - right,
                height: safeAreaTop
            )
        } else {
            hasNotch = false
            notchRect = .zero
        }
    }

    /// Height of the black bar at the top of the pill (the notch, or the fallback pill).
    public var topInset: CGFloat {
        hasNotch ? notchRect.height : Self.fallbackSize.height
    }

    /// Frame of the collapsed pill in global screen coordinates.
    public var collapsedFrame: CGRect {
        if hasNotch {
            return CGRect(
                x: notchRect.minX - Self.pillExtension,
                y: notchRect.minY,
                width: notchRect.width + 2 * Self.pillExtension,
                height: notchRect.height
            )
        }
        let size = Self.fallbackSize
        return CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// Frame of the hover-expanded panel: centered on the notch, flush with the top, kept on screen.
    public var expandedFrame: CGRect {
        panelFrame(width: Self.expandedWidth, contentHeight: Self.expandedContentHeight)
    }

    private func panelFrame(width requested: CGFloat, contentHeight: CGFloat) -> CGRect {
        let width = min(requested, screenFrame.width)
        let height = topInset + contentHeight
        let centerX = hasNotch ? notchRect.midX : screenFrame.midX
        let x = min(max(centerX - width / 2, screenFrame.minX), screenFrame.maxX - width)
        return CGRect(x: x, y: screenFrame.maxY - height, width: width, height: height)
    }

    /// Frame of the attention panel: like the hover panel, but wider, and as tall as its content.
    /// - Parameters:
    ///   - lines: how many lines the request text takes (1 or 2); the panel grows by one line height.
    ///   - hasButtons: false when only the terminal can answer, so there is no button row to make room for.
    public func attentionFrame(lines: Int = 1, hasButtons: Bool = true) -> CGRect {
        let extraLines = CGFloat(min(max(lines, 1), 2) - 1) * Self.attentionLineHeight
        let buttons = hasButtons ? 0 : Self.attentionButtonRowHeight
        return panelFrame(width: Self.attentionWidth, contentHeight: Self.attentionContentHeight + extraLines - buttons)
    }

    public func frame(for presentation: PillPresentation, attentionLines: Int = 1, attentionButtons: Bool = true) -> CGRect {
        switch presentation {
        case .collapsed: collapsedFrame
        case .hover: expandedFrame
        case .attention: attentionFrame(lines: attentionLines, hasButtons: attentionButtons)
        }
    }

    /// Radius of the two bottom corners of the collapsed pill.
    public var bottomCornerRadius: CGFloat { hasNotch ? 12 : 16 }

    /// Radius of the two bottom corners of the expanded panel.
    public var expandedBottomCornerRadius: CGFloat { 20 }
}
