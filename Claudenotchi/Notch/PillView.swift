import ClaudenotchiCore
import SwiftUI

/// Collapsed pill: black capsule hugging the notch with the mascot on the left.
struct PillView: View {
    let geometry: NotchGeometry
    let model: CompanionModel

    var body: some View {
        ZStack(alignment: .leading) {
            UnevenRoundedRectangle(
                bottomLeadingRadius: geometry.bottomCornerRadius,
                bottomTrailingRadius: geometry.bottomCornerRadius
            )
            .fill(Color.black)

            AnimatedSpriteView(state: model.state, since: model.stateSince, size: 16)
                .padding(.leading, geometry.hasNotch ? 16 : 12)
        }
    }
}
