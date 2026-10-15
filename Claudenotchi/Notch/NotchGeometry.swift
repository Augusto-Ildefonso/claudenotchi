import CoreGraphics

/// Where the pill sits on a screen. Pure value type so it can be unit tested without a display.
struct NotchGeometry: Equatable {
    /// How far the collapsed pill extends past each side of the notch, so the pill stays symmetric
    /// around the notch. The left side holds the mascot; the right side is reserved for status.
    static let pillExtension: CGFloat = 56
    /// Size of the floating pill on screens without a notch.
    static let fallbackSize = CGSize(width: 190, height: 32)

    let hasNotch: Bool
    /// Notch rectangle in global screen coordinates (origin bottom-left). Zero-sized when `hasNotch` is false.
    let notchRect: CGRect
    let screenFrame: CGRect

    /// - Parameters:
    ///   - screenFrame: `NSScreen.frame`
    ///   - safeAreaTop: `NSScreen.safeAreaInsets.top` (non-zero on notch displays)
    ///   - leftAreaWidth / rightAreaWidth: widths of `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`
    ///     (nil when the screen has no notch). Only widths are used, so the result does not depend on
    ///     whether those rects are in local or global coordinates.
    init(screenFrame: CGRect, safeAreaTop: CGFloat, leftAreaWidth: CGFloat?, rightAreaWidth: CGFloat?) {
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

    /// Frame of the collapsed pill in global screen coordinates.
    var collapsedFrame: CGRect {
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

    /// Radius of the two bottom corners.
    var bottomCornerRadius: CGFloat { hasNotch ? 12 : 16 }
}
