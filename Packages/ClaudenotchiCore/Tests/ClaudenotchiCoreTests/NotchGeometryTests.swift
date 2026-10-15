import CoreGraphics
import Testing
@testable import ClaudenotchiCore

@Suite struct NotchGeometryTests {
    /// 14" MacBook Pro built-in display: 1512x982 points, notch 185pt wide and 32pt tall.
    private func notchScreen(origin: CGPoint = .zero, extension strip: CGFloat = NotchGeometry.pillExtension) -> NotchGeometry {
        NotchGeometry(
            screenFrame: CGRect(origin: origin, size: CGSize(width: 1512, height: 982)),
            safeAreaTop: 32, leftAreaWidth: 663.5, rightAreaWidth: 663.5, collapsedExtension: strip
        )
    }

    private func plainScreen(origin: CGPoint = .zero) -> NotchGeometry {
        NotchGeometry(
            screenFrame: CGRect(origin: origin, size: CGSize(width: 1920, height: 1080)),
            safeAreaTop: 0, leftAreaWidth: nil, rightAreaWidth: nil
        )
    }

    // MARK: notch detection

    @Test func findsTheNotchFromTheAuxiliaryAreas() {
        let g = notchScreen()
        #expect(g.hasNotch)
        #expect(g.notchRect == CGRect(x: 663.5, y: 950, width: 185, height: 32))
    }

    @Test func screensWithoutASafeAreaHaveNoNotch() {
        let g = plainScreen()
        #expect(g.hasNotch == false)
        #expect(g.notchRect == .zero)
    }

    @Test func safeAreaWithoutAuxiliaryAreasIsNotANotch() {
        let g = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                              safeAreaTop: 30, leftAreaWidth: nil, rightAreaWidth: nil)
        #expect(g.hasNotch == false)
    }

    // MARK: collapsed pill

    @Test func collapsedPillHugsTheNotchWithEqualBlackOnBothSides() {
        let g = notchScreen()
        let pill = g.collapsedFrame
        #expect(pill.minX == g.notchRect.minX - NotchGeometry.pillExtension)
        #expect(pill.maxX == g.notchRect.maxX + NotchGeometry.pillExtension)
        #expect(pill.midX == g.notchRect.midX)
        #expect(pill.height == 32)
        #expect(pill.maxY == 982) // flush with the top edge
    }

    // MARK: the strip beside the notch is only as wide as the mascot needs

    @Test func theStripFitsTheMascotWithAMarginOnEachSide() {
        #expect(NotchGeometry.collapsedExtension(forMascotSize: 16) == 28)
        #expect(NotchGeometry.collapsedExtension(forMascotSize: 24) == 36)
        #expect(NotchGeometry.collapsedExtension(forMascotSize: 32) == 44)
    }

    @Test func aBiggerMascotNeedsAWiderStrip() {
        #expect(NotchGeometry.collapsedExtension(forMascotSize: 32) > NotchGeometry.collapsedExtension(forMascotSize: 24))
    }

    @Test func theStripIsMuchNarrowerThanTheOldFixedOne() {
        #expect(NotchGeometry.collapsedExtension(forMascotSize: 24) < NotchGeometry.pillExtension)
    }

    @Test func theCollapsedPillUsesTheGivenStripOnBothSides() {
        let g = notchScreen(extension: 36)
        let pill = g.collapsedFrame
        #expect(pill.minX == g.notchRect.minX - 36)
        #expect(pill.maxX == g.notchRect.maxX + 36)
        #expect(pill.midX == g.notchRect.midX, "still symmetric around the notch")
        #expect(pill.width == g.notchRect.width + 72)
    }

    @Test func aNarrowerStripCoversLessOfTheMenuBar() {
        #expect(notchScreen(extension: 36).collapsedFrame.width < notchScreen(extension: 56).collapsedFrame.width)
    }

    @Test func theDefaultStripIsUnchanged() {
        #expect(notchScreen().collapsedFrame == notchScreen(extension: NotchGeometry.pillExtension).collapsedFrame)
    }

    @Test func theStripSizeDoesNotChangeTheHoverOrAttentionPanels() {
        #expect(notchScreen(extension: 36).expandedFrame == notchScreen(extension: 56).expandedFrame)
        #expect(notchScreen(extension: 36).attentionFrame() == notchScreen(extension: 56).attentionFrame())
    }

    @Test func aNotchlessScreenIgnoresTheStrip() {
        let g = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080), safeAreaTop: 0,
                              leftAreaWidth: nil, rightAreaWidth: nil, collapsedExtension: 36)
        #expect(g.collapsedFrame.size == NotchGeometry.fallbackSize)
    }

    @Test func collapsedPillOnASecondaryDisplayUsesGlobalCoordinates() {
        let g = notchScreen(origin: CGPoint(x: -1512, y: 100))
        let expectedMidX: CGFloat = -1512 + 756
        let expectedTop: CGFloat = 100 + 982
        #expect(g.collapsedFrame.midX == expectedMidX)
        #expect(g.collapsedFrame.maxY == expectedTop)
    }

    @Test func fallbackPillIsCenteredAtTheTopOfAPlainScreen() {
        let pill = plainScreen().collapsedFrame
        #expect(pill.size == NotchGeometry.fallbackSize)
        #expect(pill.midX == 960)
        #expect(pill.maxY == 1080)
    }

    @Test func cornerRadiusDiffersBetweenNotchAndFallback() {
        #expect(notchScreen().bottomCornerRadius == 12)
        #expect(plainScreen().bottomCornerRadius == 16)
    }

    // MARK: expanded pill

    @Test func expandedPanelIsCenteredOnTheNotchAndFlushWithTheTop() {
        let g = notchScreen()
        let panel = g.expandedFrame
        #expect(panel.width == NotchGeometry.expandedWidth)
        #expect(panel.midX == g.notchRect.midX)
        #expect(panel.maxY == 982)
    }

    @Test func expandedPanelAddsContentHeightBelowTheNotch() {
        let g = notchScreen()
        #expect(g.expandedFrame.height == g.notchRect.height + NotchGeometry.expandedContentHeight)
    }

    @Test func expandedPanelOnAPlainScreenIsCenteredToo() {
        let g = plainScreen()
        #expect(g.expandedFrame.midX == 960)
        #expect(g.expandedFrame.maxY == 1080)
        #expect(g.expandedFrame.height == NotchGeometry.fallbackSize.height + NotchGeometry.expandedContentHeight)
    }

    @Test func expandedPanelContainsTheCollapsedPill() {
        for g in [notchScreen(), plainScreen()] {
            #expect(g.expandedFrame.contains(g.collapsedFrame))
        }
    }

    @Test func expandedPanelNeverExceedsAnArrowScreen() {
        let narrow = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 300, height: 600),
                                   safeAreaTop: 0, leftAreaWidth: nil, rightAreaWidth: nil)
        #expect(narrow.expandedFrame.width <= 300)
        #expect(narrow.expandedFrame.minX >= 0)
    }

    // MARK: attention panel (permission prompt)

    @Test func attentionPanelIsCenteredOnTheNotchAndFlushWithTheTop() {
        let g = notchScreen()
        let panel = g.attentionFrame()
        #expect(panel.width == NotchGeometry.attentionWidth)
        #expect(panel.midX == g.notchRect.midX)
        #expect(panel.maxY == 982)
        #expect(panel.height == g.notchRect.height + NotchGeometry.attentionContentHeight)
    }

    @Test func attentionPanelHugsItsContentWithoutAnEmptyStrip() {
        // Header row + buttons + padding come to roughly 98pt; a taller panel leaves a black gap under the buttons.
        #expect(NotchGeometry.attentionContentHeight <= 100)
        #expect(NotchGeometry.attentionContentHeight >= 90)
    }

    @Test func aRequestThatWrapsToASecondLineGetsOneMoreLineOfHeight() {
        let g = notchScreen()
        #expect(g.attentionFrame(lines: 2).height == g.attentionFrame(lines: 1).height + NotchGeometry.attentionLineHeight)
    }

    @Test func withoutButtonsThePanelDropsTheButtonRow() {
        let g = notchScreen()
        let with = g.attentionFrame(lines: 1, hasButtons: true)
        let without = g.attentionFrame(lines: 1, hasButtons: false)
        #expect(without.height == with.height - NotchGeometry.attentionButtonRowHeight)
        #expect(without.maxY == with.maxY)
        #expect(without.midX == with.midX)
        #expect(without.width == with.width)
    }

    @Test func theButtonRowSavingsCombineWithExtraLines() {
        let g = notchScreen()
        #expect(g.attentionFrame(lines: 2, hasButtons: false).height
                == g.notchRect.height + NotchGeometry.attentionContentHeight + NotchGeometry.attentionLineHeight - NotchGeometry.attentionButtonRowHeight)
    }

    @Test func buttonsAreTheDefault() {
        let g = notchScreen()
        #expect(g.attentionFrame() == g.attentionFrame(lines: 1, hasButtons: true))
    }

    @Test func attentionLinesAreClampedToOneOrTwo() {
        let g = notchScreen()
        #expect(g.attentionFrame(lines: 0) == g.attentionFrame(lines: 1))
        #expect(g.attentionFrame(lines: 9) == g.attentionFrame(lines: 2))
    }

    @Test func extraLinesGrowDownwardAndKeepTheTopFlush() {
        let g = notchScreen()
        #expect(g.attentionFrame(lines: 2).maxY == g.attentionFrame(lines: 1).maxY)
        #expect(g.attentionFrame(lines: 2).midX == g.attentionFrame(lines: 1).midX)
    }

    @Test func attentionPanelIsRoomierThanTheHoverPanel() {
        for g in [notchScreen(), plainScreen()] {
            #expect(g.attentionFrame().width > g.expandedFrame.width)
            #expect(g.attentionFrame().height > g.expandedFrame.height)
            #expect(g.attentionFrame().contains(g.expandedFrame))
        }
    }

    @Test func attentionPanelStaysOnASmallScreen() {
        let narrow = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 300, height: 600),
                                   safeAreaTop: 0, leftAreaWidth: nil, rightAreaWidth: nil)
        #expect(narrow.attentionFrame().width <= 300)
        #expect(narrow.attentionFrame().minX >= 0)
    }

    @Test func frameForEachPresentation() {
        let g = notchScreen()
        #expect(g.frame(for: .collapsed) == g.collapsedFrame)
        #expect(g.frame(for: .hover) == g.expandedFrame)
        #expect(g.frame(for: .attention) == g.attentionFrame())
        #expect(g.frame(for: .attention, attentionLines: 2) == g.attentionFrame(lines: 2))
        #expect(g.frame(for: .attention, attentionLines: 1, attentionButtons: false) == g.attentionFrame(lines: 1, hasButtons: false))
    }

    @Test func topInsetIsTheHeightOfTheBlackBarAboveTheContent() {
        #expect(notchScreen().topInset == 32)
        #expect(plainScreen().topInset == NotchGeometry.fallbackSize.height)
    }

    // MARK: the closed pill (where the show/hide animation starts and ends)

    @Test func theClosedPillOnANotchScreenIsTheNotchItself() {
        let g = notchScreen()
        #expect(g.closedFrame == g.notchRect, "it widens out of the notch, so it begins exactly over it")
    }

    @Test func theClosedPillOnAPlainScreenIsANarrowStubAtTheTopCenter() {
        let g = plainScreen()
        #expect(g.closedFrame.midX == 960)
        #expect(g.closedFrame.maxY == 1080)
        #expect(g.closedFrame.height == NotchGeometry.fallbackSize.height)
        #expect(g.closedFrame.width < NotchGeometry.fallbackSize.width / 2)
    }

    @Test func everyPresentationGrowsOutOfTheClosedPill() {
        for g in [notchScreen(), notchScreen(extension: 44), plainScreen()] {
            for presentation in [PillPresentation.collapsed, .hover, .attention] {
                #expect(g.frame(for: presentation).contains(g.closedFrame), "\(presentation)")
            }
        }
    }

    @Test func theClosedPillStaysCenteredOnASecondaryDisplay() {
        let g = notchScreen(origin: CGPoint(x: -1512, y: 100))
        #expect(g.closedFrame.midX == g.collapsedFrame.midX)
        #expect(g.closedFrame.maxY == g.collapsedFrame.maxY)
    }
}

