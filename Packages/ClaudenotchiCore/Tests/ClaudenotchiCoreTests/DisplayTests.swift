import CoreGraphics
import Testing
@testable import ClaudenotchiCore

private func screen(
    _ id: String, notch: Bool = false, main: Bool = false, name: String? = nil,
    frame: CGRect = CGRect(x: 0, y: 0, width: 1512, height: 982)
) -> ScreenInfo {
    ScreenInfo(
        id: id, name: name ?? id, frame: frame,
        safeAreaTop: notch ? 32 : 0,
        leftAreaWidth: notch ? 663.5 : nil, rightAreaWidth: notch ? 663.5 : nil,
        isMain: main
    )
}

@Suite struct DisplayPreferenceTests {
    @Test func storedValuesRoundTrip() {
        for preference in [DisplayPreference.automatic, .main, .display(id: "ABC-123")] {
            #expect(DisplayPreference(storedValue: preference.storedValue) == preference)
        }
    }

    @Test func theStoredFormIsReadable() {
        #expect(DisplayPreference.automatic.storedValue == "auto")
        #expect(DisplayPreference.main.storedValue == "main")
        #expect(DisplayPreference.display(id: "ABC-123").storedValue == "display:ABC-123")
    }

    @Test func anythingUnknownMeansAutomatic() {
        #expect(DisplayPreference(storedValue: "") == .automatic)
        #expect(DisplayPreference(storedValue: "garbage") == .automatic)
        #expect(DisplayPreference(storedValue: "display:") == .automatic)
    }
}

@Suite struct DisplayChooserTests {
    @Test func noScreensMeansNoChoice() {
        #expect(DisplayChooser.choose(.automatic, from: []) == nil)
        #expect(DisplayChooser.choose(.main, from: []) == nil)
        #expect(DisplayChooser.choose(.display(id: "x"), from: []) == nil)
    }

    @Test func automaticPrefersTheScreenWithTheNotch() {
        let external = screen("ext", main: true)
        let builtIn = screen("built-in", notch: true)
        #expect(DisplayChooser.choose(.automatic, from: [external, builtIn])?.id == "built-in")
        #expect(DisplayChooser.choose(.automatic, from: [builtIn, external])?.id == "built-in")
    }

    @Test func automaticFallsBackToTheMainScreenWithoutANotch() {
        let side = screen("side")
        let main = screen("main", main: true)
        #expect(DisplayChooser.choose(.automatic, from: [side, main])?.id == "main")
    }

    @Test func automaticFallsBackToTheFirstScreenWhenNoneIsMain() {
        #expect(DisplayChooser.choose(.automatic, from: [screen("a"), screen("b")])?.id == "a")
    }

    @Test func mainChoosesTheMainScreenEvenWhenAnotherHasANotch() {
        let main = screen("main", main: true)
        let builtIn = screen("built-in", notch: true)
        #expect(DisplayChooser.choose(.main, from: [builtIn, main])?.id == "main")
    }

    @Test func aSpecificDisplayIsChosenWhenConnected() {
        let screens = [screen("a", main: true), screen("b"), screen("c", notch: true)]
        #expect(DisplayChooser.choose(.display(id: "b"), from: screens)?.id == "b")
    }

    @Test func aDisconnectedDisplayFallsBackToAutomatic() {
        let screens = [screen("ext", main: true), screen("built-in", notch: true)]
        #expect(DisplayChooser.choose(.display(id: "unplugged"), from: screens)?.id == "built-in")
    }

    @Test func mainWithNoMainFlagFallsBackToAutomatic() {
        #expect(DisplayChooser.choose(.main, from: [screen("a"), screen("b", notch: true)])?.id == "b")
    }
}

@Suite struct ScreenInfoTests {
    @Test func aNotchNeedsASafeAreaAndBothSideAreas() {
        #expect(screen("a", notch: true).hasNotch)
        #expect(screen("a").hasNotch == false)
        let partial = ScreenInfo(id: "p", name: "p", frame: .zero, safeAreaTop: 30, leftAreaWidth: nil, rightAreaWidth: 600, isMain: false)
        #expect(partial.hasNotch == false)
    }

    @Test func geometryMatchesTheScreen() {
        let info = screen("a", notch: true, frame: CGRect(x: -1512, y: 0, width: 1512, height: 982))
        #expect(info.geometry.hasNotch)
        let expectedMidX: CGFloat = -1512 + 756
        #expect(info.geometry.collapsedFrame.midX == expectedMidX)
        let plain = screen("b", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        #expect(plain.geometry.hasNotch == false)
        let expectedPlainMidX: CGFloat = 960
        #expect(plain.geometry.collapsedFrame.midX == expectedPlainMidX)
    }

    @Test func pretendingThereIsNoNotchGivesTheFallbackPill() {
        let info = screen("a", notch: true)
        let fallback = info.withoutNotch
        #expect(fallback.hasNotch == false)
        #expect(fallback.geometry.collapsedFrame.size == NotchGeometry.fallbackSize)
        #expect(fallback.id == info.id && fallback.frame == info.frame)
    }
}
