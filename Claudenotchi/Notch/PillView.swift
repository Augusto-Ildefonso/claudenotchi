import ClaudenotchiCore
import SwiftUI

/// The pill: a black shape hugging the notch. It shows the mascot beside the notch; on hover it expands
/// with a status line; when Claude needs you it opens wider with the request and Approve / Deny.
struct PillView: View {
    let geometry: NotchGeometry
    let model: CompanionModel

    private static let approveColor = Color(red: 0x2F / 255, green: 0x9E / 255, blue: 0x5B / 255)
    private static let denyColor = Color(red: 0xC0 / 255, green: 0x38 / 255, blue: 0x3D / 255)

    var body: some View {
        let presentation = model.presentation
        let radius = presentation == .collapsed ? geometry.bottomCornerRadius : geometry.expandedBottomCornerRadius
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius)

        // The black shape is the *background* of a view that simply takes the window's size. The three
        // layouts are overlays: they have fixed, different sizes, and as siblings in a ZStack the largest
        // would inflate the shape and push its rounded corners out of the visible window.
        Color.clear
            .overlay(alignment: .top) {
                ZStack(alignment: .top) {
                    collapsedContent.opacity(presentation == .collapsed ? 1 : 0)
                    hoverContent.opacity(presentation == .hover ? 1 : 0)
                    attentionContent.opacity(presentation == .attention ? 1 : 0)
                }
            }
            .background(shape.fill(Color.black))
            .clipShape(shape)
            .animation(.easeOut(duration: 0.2), value: presentation)
    }

    // MARK: Collapsed

    /// 16px mascot in the left extension, vertically centered in the notch-height bar.
    private var collapsedContent: some View {
        AnimatedSpriteView(state: model.state, since: model.stateSince, size: 16)
            .padding(.leading, geometry.hasNotch ? 16 : 12)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                        Text(model.currentPrompt == nil ? "Needs your input" : "Claude needs your permission")
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
                    if model.currentPrompt != nil {
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
        NotchGeometry.attentionContentHeight + (model.attentionLines > 1 ? NotchGeometry.attentionLineHeight : 0)
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
