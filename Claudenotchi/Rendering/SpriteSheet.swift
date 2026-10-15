import AppKit
import SwiftUI

/// A horizontal strip of square frames, as produced by `scripts/gen_sprites.py`.
struct SpriteSheet {
    let image: CGImage
    let frameSize: Int

    var frameCount: Int { image.width / frameSize }

    func frame(_ index: Int) -> CGImage? {
        guard index >= 0, index < frameCount else { return nil }
        return image.cropping(to: CGRect(x: index * frameSize, y: 0, width: frameSize, height: frameSize))
    }

    /// Loads `<state>@<size>.png` from the bundle (flat or inside a `Sprites` folder).
    static func load(state: String, size: Int, bundle: Bundle = .main) -> SpriteSheet? {
        let name = "\(state)@\(size)"
        guard let url = bundle.url(forResource: name, withExtension: "png")
                ?? bundle.url(forResource: name, withExtension: "png", subdirectory: "Sprites"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return SpriteSheet(image: image, frameSize: size)
    }
}

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
