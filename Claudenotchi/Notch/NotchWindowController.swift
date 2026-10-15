import AppKit
import ClaudenotchiCore
import SwiftUI

/// Owns the notch panel: keeps it aligned with the screen's notch and expands it on hover.
final class NotchWindowController {
    private let model: CompanionModel
    private var panel: NotchPanel?
    private var geometry = NotchWindowController.currentGeometry()
    private var observer: NSObjectProtocol?

    private var hover = HoverIntent(expandDelay: AppSettings.hoverDelay())
    private var ticker: Task<Void, Never>?

    init(model: CompanionModel) {
        self.model = model
    }

    func show() {
        geometry = Self.currentGeometry()
        let panel = NotchPanel(contentRect: geometry.collapsedFrame)
        panel.contentView = makeContentView()
        panel.orderFrontRegardless()
        self.panel = panel

        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
    }

    /// The SwiftUI view lives inside a plain container. As the window's own content view it would
    /// resize the window to SwiftUI's ideal size; as a subview it just fills whatever frame we set.
    private func makeContentView() -> NSView {
        let container = NSView()
        let hosting = HoverHostingView(rootView: PillView(geometry: geometry, model: model))
        hosting.sizingOptions = []
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        hosting.onMouseEntered = { [weak self] in self?.mouseEntered() }
        hosting.onMouseExited = { [weak self] in self?.mouseExited() }
        container.addSubview(hosting)
        return container
    }

    private func reposition() {
        guard let panel else { return }
        geometry = Self.currentGeometry()
        panel.contentView = makeContentView()
        panel.setFrame(model.isExpanded ? geometry.expandedFrame : geometry.collapsedFrame, display: true)
    }

    // MARK: Hover

    private func mouseEntered() {
        hover.mouseEntered(at: Date())
        evaluateHover()
        startTickerIfNeeded()
    }

    private func mouseExited() {
        hover.mouseExited(at: Date())
        evaluateHover()
        startTickerIfNeeded()
    }

    /// Re-reads the user's delay on every evaluation so a change in the menu applies right away.
    private func evaluateHover() {
        hover.expandDelay = AppSettings.hoverDelay()
        hover.tick(now: Date())
        setExpanded(hover.isExpanded)
    }

    private func startTickerIfNeeded() {
        guard ticker == nil, hover.needsTicks else { return }
        ticker = Task {
            while hover.needsTicks {
                try? await Task.sleep(for: .milliseconds(40))
                evaluateHover()
            }
            ticker = nil
        }
    }

    private func setExpanded(_ expanded: Bool) {
        guard let panel, expanded != model.isExpanded else { return }
        model.isExpanded = expanded
        let target = expanded ? geometry.expandedFrame : geometry.collapsedFrame
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
        }
    }

    /// Prefers a screen with a notch; falls back to the main screen.
    private static func currentGeometry() -> NotchGeometry {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        return NotchGeometry(
            screenFrame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            leftAreaWidth: screen.auxiliaryTopLeftArea?.width,
            rightAreaWidth: screen.auxiliaryTopRightArea?.width
        )
    }
}
