import ClaudenotchiCore
import SwiftUI

/// Draws one sprite frame with nearest-neighbor scaling (no smoothing).
struct SpriteView: View {
    let image: CGImage
    let size: CGFloat

    var body: some View {
        Image(decorative: image, scale: 1)
            .interpolation(.none)
            .resizable()
            .frame(width: size, height: size)
    }
}

/// Plays a state's looping animation, starting from `since` so it restarts on every state change.
struct AnimatedSpriteView: View {
    let state: CompanionState
    let since: Date
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The 32px art only at 32pt or more (1pt per art pixel); smaller sizes scale the 16px art, which
        // stays crisp at 16, 24 and 32pt (2, 3 and 4 screen pixels per art pixel on a 2x display).
        if let clip = SpriteLibrary.shared.clip(for: state, size: size >= 32 ? 32 : 16) {
            if reduceMotion || clip.frames.count == 1 {
                SpriteView(image: clip.frames[0], size: size)
            } else {
                TimelineView(.periodic(from: since, by: SpriteAnimation.frameDuration(fps: clip.fps))) { context in
                    let index = SpriteAnimation.frameIndex(
                        elapsed: context.date.timeIntervalSince(since),
                        frames: clip.frames.count,
                        fps: clip.fps
                    )
                    SpriteView(image: clip.frames[index], size: size)
                }
                .id(since)
            }
        }
    }
}
