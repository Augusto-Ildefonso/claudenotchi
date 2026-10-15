import ClaudenotchiCore
import SwiftUI

/// The pill: a black shape hugging the notch. Collapsed it shows the mascot beside the notch;
/// hovered it expands to show the mascot larger with a status line and the project folder.
struct PillView: View {
    let geometry: NotchGeometry
    let model: CompanionModel

    var body: some View {
        let expanded = model.isExpanded
        let radius = expanded ? geometry.expandedBottomCornerRadius : geometry.bottomCornerRadius

        ZStack(alignment: .top) {
            UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius)
                .fill(Color.black)

            collapsedContent
                .opacity(expanded ? 0 : 1)

            expandedContent
                .opacity(expanded ? 1 : 0)
        }
        .animation(.easeOut(duration: 0.2), value: expanded)
    }

    /// 16px mascot in the left extension, vertically centered in the notch-height bar.
    private var collapsedContent: some View {
        AnimatedSpriteView(state: model.state, since: model.stateSince, size: 16)
            .padding(.leading, geometry.hasNotch ? 16 : 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: geometry.topInset)
    }

    /// Fixed-width layout so the content does not reflow while the panel animates its size.
    private var expandedContent: some View {
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
}
