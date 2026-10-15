import AppKit
import SwiftUI

/// Plays a looping sprite animation as a Core Animation keyframe animation on a layer. The render server flips
/// the frames, so the app does no work per frame; driving the same animation from a SwiftUI `TimelineView`
/// re-rendered the view ten times a second and cost about 3% of a core while the mascot was only idling.
struct LayerSpriteView: NSViewRepresentable {
    let frames: [CGImage]
    let fps: Double

    func makeNSView(context: Context) -> SpriteLayerView {
        SpriteLayerView()
    }

    func updateNSView(_ view: SpriteLayerView, context: Context) {
        view.show(frames: frames, fps: fps)
    }
}

final class SpriteLayerView: NSView {
    private static let animationKey = "sprite"
    private var shown: (first: UnsafeMutableRawPointer, count: Int, fps: Double)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        // Nearest-neighbor: scaling the pixel art must never smooth it.
        layer?.magnificationFilter = .nearest
        layer?.minificationFilter = .nearest
        layer?.contentsGravity = .resize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layer?.contentsScale = window?.backingScaleFactor ?? 2
    }

    /// Starts (or keeps running) the animation for `frames`. Calling this again with the same frames does not
    /// restart it, so SwiftUI can re-evaluate the view freely.
    func show(frames: [CGImage], fps: Double) {
        guard let layer, let first = frames.first else { return }
        let key = (first: Unmanaged.passUnretained(first).toOpaque(), count: frames.count, fps: fps)
        if let shown, shown.first == key.first, shown.count == key.count, shown.fps == key.fps { return }
        shown = key

        layer.removeAnimation(forKey: Self.animationKey)
        layer.contents = first
        guard frames.count > 1, fps > 0 else { return }

        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = frames
        animation.calculationMode = .discrete // hold each frame, no blending between them
        animation.duration = Double(frames.count) / fps
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: Self.animationKey)
    }
}
