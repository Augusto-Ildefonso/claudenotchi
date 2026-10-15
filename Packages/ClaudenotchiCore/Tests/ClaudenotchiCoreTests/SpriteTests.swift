import Foundation
import ImageIO
import Testing
@testable import ClaudenotchiCore

/// `Claudenotchi/Sprites/` in the repo, located relative to this file.
private let spritesDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // ClaudenotchiCoreTests
    .deletingLastPathComponent() // Tests
    .deletingLastPathComponent() // ClaudenotchiCore
    .deletingLastPathComponent() // Packages
    .deletingLastPathComponent() // repo root
    .appendingPathComponent("Claudenotchi/Sprites")

private func repoManifest() throws -> SpriteManifest {
    try SpriteManifest(json: Data(contentsOf: spritesDirectory.appendingPathComponent("manifest.json")))
}

private func pixelSize(of file: URL) -> (width: Int, height: Int)? {
    guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    return (image.width, image.height)
}

@Suite struct SpriteManifestTests {
    @Test func decodesFramesFpsAndFiles() throws {
        let json = #"""
        {"states":{"coding":{"frames":4,"fps":6,"size16":"coding@16.png","size32":null},
                   "alert":{"frames":4,"fps":8,"size16":"alert@16.png","size32":"alert@32.png","frames32":2}},
         "idle":["waiting","tennis"]}
        """#
        let manifest = try SpriteManifest(json: Data(json.utf8))
        #expect(manifest.states["coding"] == .init(frames: 4, fps: 6, size16: "coding@16.png", size32: nil, frames32: nil))
        #expect(manifest.states["alert"]?.size32 == "alert@32.png")
        #expect(manifest.states["alert"]?.frames32 == 2)
        #expect(manifest.idle == ["waiting", "tennis"])
    }

    @Test func looksUpEntriesBySpriteName() throws {
        let json = #"{"states":{"alert":{"frames":4,"fps":8,"size16":"alert@16.png"}},"idle":[]}"#
        let manifest = try SpriteManifest(json: Data(json.utf8))
        #expect(manifest.entry(for: .needsInput)?.frames == 4) // needsInput is drawn by the "alert" sprite
        #expect(manifest.entry(for: .coding) == nil)
    }

    @Test func invalidJSONThrows() {
        #expect(throws: (any Error).self) { try SpriteManifest(json: Data("nope".utf8)) }
    }

    @Test func repoManifestHasASpriteForEveryState() throws {
        let manifest = try repoManifest()
        for state in CompanionState.allCases {
            #expect(manifest.entry(for: state) != nil, "no sprite for \(state)")
        }
    }

    @Test func repoManifestValuesAreSane() throws {
        for (name, entry) in try repoManifest().states {
            #expect(entry.frames >= 1, "\(name) frames")
            #expect(entry.fps > 0, "\(name) fps")
        }
    }

    @Test func spritePNGsMatchTheManifest() throws {
        for (name, entry) in try repoManifest().states {
            let strip16 = try #require(pixelSize(of: spritesDirectory.appendingPathComponent(entry.size16)), "\(name) 16px png")
            #expect(strip16 == (16 * entry.frames, 16), "\(name) 16px strip size")
            if let file32 = entry.size32 {
                let strip32 = try #require(pixelSize(of: spritesDirectory.appendingPathComponent(file32)), "\(name) 32px png")
                #expect(strip32 == (32 * (entry.frames32 ?? 1), 32), "\(name) 32px strip size")
            }
        }
    }

    @Test func repoIdleListOnlyNamesRealStates() throws {
        let known = Set(CompanionState.allCases.map(\.rawValue))
        for name in try repoManifest().idle {
            #expect(known.contains(name), "idle entry \(name)")
        }
    }
}

@Suite struct SpriteAnimationTests {
    @Test func startsOnTheFirstFrame() {
        #expect(SpriteAnimation.frameIndex(elapsed: 0, frames: 4, fps: 6) == 0)
    }

    @Test func advancesOneFramePerFrameDuration() {
        #expect(SpriteAnimation.frameIndex(elapsed: 1.0 / 6, frames: 4, fps: 6) == 1)
        #expect(SpriteAnimation.frameIndex(elapsed: 2.0 / 6 + 0.01, frames: 4, fps: 6) == 2)
    }

    @Test func staysOnAFrameUntilItsTimeIsUp() {
        #expect(SpriteAnimation.frameIndex(elapsed: 0.16, frames: 4, fps: 6) == 0)
    }

    @Test func loopsBackToTheStart() {
        #expect(SpriteAnimation.frameIndex(elapsed: 4.0 / 6 + 0.01, frames: 4, fps: 6) == 0)
        #expect(SpriteAnimation.frameIndex(elapsed: 10, frames: 4, fps: 6) == 60 % 4)
    }

    @Test func singleFrameAlwaysShowsThatFrame() {
        #expect(SpriteAnimation.frameIndex(elapsed: 123, frames: 1, fps: 8) == 0)
    }

    @Test func negativeElapsedTimeShowsTheFirstFrame() {
        #expect(SpriteAnimation.frameIndex(elapsed: -5, frames: 4, fps: 6) == 0)
    }

    @Test func nonPositiveFpsOrFramesShowTheFirstFrame() {
        #expect(SpriteAnimation.frameIndex(elapsed: 5, frames: 4, fps: 0) == 0)
        #expect(SpriteAnimation.frameIndex(elapsed: 5, frames: 0, fps: 6) == 0)
    }

    @Test func frameDurationIsTheInverseOfFps() {
        #expect(SpriteAnimation.frameDuration(fps: 8) == 0.125)
        #expect(SpriteAnimation.frameDuration(fps: 0) == 1)
    }
}
