import ClaudenotchiCore
import SwiftUI

/// The pill: a black shape hugging the notch. It shows the mascot beside the notch; on hover it expands
/// with a status line; when Claude needs you it opens wider with the request and Approve / Deny.
struct PillView: View {
    let geometry: NotchGeometry
    let model: CompanionModel

    @AppStorage(AppSettings.mascotSizeKey) private var mascotSize = AppSettings.defaultMascotSize

    private static let approveColor = Color(red: 0x2F / 255, green: 0x9E / 255, blue: 0x5B / 255)
    private static let denyColor = Color(red: 0xC0 / 255, green: 0x38 / 255, blue: 0x3D / 255)

    var body: some View {
        let presentation = model.presentation
        let radius = presentation == .collapsed ? geometry.bottomCornerRadius : geometry.expandedBottomCornerRadius
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius)

        // The black shape is the *background* of a view that simply takes the window's size. Each layout
        // is its own overlay with its own alignment: they have fixed, different sizes, and as siblings in
        // one ZStack the widest would set the stack's width, inflate the shape (pushing its rounded corners
        // out of the window) and shift the collapsed mascot, which hugs the left edge, off screen.
        Color.clear
            .overlay(alignment: .topLeading) {
                collapsedContent.opacity(presentation == .collapsed ? 1 : 0)
            }
            .overlay(alignment: .top) {
                hoverContent.opacity(presentation == .hover ? 1 : 0)
            }
            .overlay(alignment: .top) {
                attentionContent.opacity(presentation == .attention ? 1 : 0)
            }
            .background(shape.fill(Color.black))
            .clipShape(shape)
            .animation(.easeOut(duration: 0.2), value: presentation)
    }

    // MARK: Collapsed

    /// The mascot centered in the small strip left of the notch (the strip is only as wide as the mascot needs),
    /// vertically centered in the notch-height bar. Its size is the user's choice; see `AppSettings.mascotSizeOptions`.
    private var collapsedContent: some View {
        let size = CGFloat(mascotSize)
        let leading = geometry.hasNotch ? max(2, (geometry.collapsedStrip - size) / 2) : 12
        return HStack(spacing: 8) {
            AnimatedSpriteView(state: model.state, since: model.stateSince, size: size)
            if !geometry.hasNotch {
                // No notch to anchor to: the floating pill says what is going on next to the mascot.
                Text(model.state.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(white: 0.7))
                    .lineLimit(1)
            }
        }
        .padding(.leading, leading)
        .padding(.trailing, 12)
        .frame(maxWidth: geometry.collapsedFrame.width, alignment: .leading)
        .frame(height: geometry.topInset)
    }

    // MARK: Hover

    /// Fixed-width layout so the content does not reflow while the panel animates its size.
    private var hoverContent: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: geometry.topInset) // the notch itself
            HStack(spacing: 12) {
                AnimatedSpriteView(state: model.state, since: model.stateSince, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.state.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(model.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(white: 0.6))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let usage = model.usage, let summary = usage.summary {
                        HStack(spacing: 8) {
                            Text(summary)
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(Color(white: 0.6))
                            if let fraction = usage.contextFraction {
                                ContextBar(fraction: fraction)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: NotchGeometry.expandedContentHeight)
        }
        .frame(width: NotchGeometry.expandedWidth)
    }

    // MARK: Attention

    private var attentionContent: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: geometry.topInset) // the notch itself
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    AnimatedSpriteView(state: model.state, since: model.stateSince, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.hasAttentionButtons ? "Claude needs your permission" : "Needs your input")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(model.attentionMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(Color(white: 0.78))
                            .lineLimit(2)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 10) {
                    if model.hasAttentionButtons {
                        Button("Approve") { model.approve() }
                            .buttonStyle(PillButtonStyle(color: Self.approveColor))
                            .accessibilityLabel("Approve")
                            .accessibilityHint("Lets Claude go ahead with: \(model.attentionMessage)")
                        Button("Deny") { model.deny() }
                            .buttonStyle(PillButtonStyle(color: Self.denyColor))
                            .accessibilityLabel("Deny")
                            .accessibilityHint("Stops Claude from doing: \(model.attentionMessage)")
                    }
                    Spacer(minLength: 0)
                    Text(attentionHint)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(white: 0.55))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .frame(height: attentionHeight, alignment: .top)
        }
        .frame(width: NotchGeometry.attentionWidth)
        .contentShape(Rectangle())
        .onTapGesture { model.focusTerminal() } // the buttons handle their own clicks
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Focus terminal") { model.focusTerminal() }
    }

    /// Content height for the current request text: one line, or one line taller when it wraps.
    private var attentionHeight: CGFloat {
        NotchGeometry.attentionContentHeight
            + (model.attentionLines > 1 ? NotchGeometry.attentionLineHeight : 0)
            - (model.hasAttentionButtons ? 0 : NotchGeometry.attentionButtonRowHeight)
    }

    private var attentionHint: String {
        let more = model.prompts.count - 1
        return more > 0 ? "\(more) more waiting · click to focus terminal" : "click to focus terminal"
    }
}

/// Rounded, solid buttons as in the Concept mockups.
private struct PillButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(color.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// A thin bar showing how full the context is; it warms from green to red as it fills.
private struct ContextBar: View {
    let fraction: Double

    private var color: Color {
        switch fraction {
        case ..<0.6: Color(red: 0.36, green: 0.76, blue: 0.48)
        case ..<0.85: Color(red: 0.96, green: 0.77, blue: 0.26)
        default: Color(red: 0.90, green: 0.28, blue: 0.30)
        }
    }

    var body: some View {
        Capsule()
            .fill(Color(white: 0.2))
            .frame(width: 64, height: 4)
            .overlay(alignment: .leading) {
                Capsule().fill(color).frame(width: 64 * min(1, max(0, fraction)), height: 4)
            }
            .accessibilityHidden(true) // the percentage is already in the text next to it
    }
}
