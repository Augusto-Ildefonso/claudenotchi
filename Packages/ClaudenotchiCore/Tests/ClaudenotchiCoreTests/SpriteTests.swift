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

    @Test func everyStateHasAFull32pxStripForTheExpandedView() throws {
        for (name, entry) in try repoManifest().states {
            #expect(entry.size32 != nil, "\(name) has no 32px strip")
            #expect(entry.frames32 == entry.frames, "\(name) 32px strip should have every frame")
        }
    }

    @Test func repoIdleListOnlyNamesRealStates() throws {
        let known = Set(CompanionState.allCases.map(\.rawValue))
        for name in try repoManifest().idle {
            #expect(known.contains(name), "idle entry \(name)")
        }
    }
}
