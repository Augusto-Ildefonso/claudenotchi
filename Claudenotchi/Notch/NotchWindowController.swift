import AppKit
import ClaudenotchiCore
import Observation
import SwiftUI

/// Owns the notch panel: keeps it aligned with the screen's notch and expands it on hover.
final class NotchWindowController {
    private let model: CompanionModel
    private var panel: NotchPanel?
    private var geometry = NotchWindowController.currentGeometry()
    private var preferenceObserver: DefaultsKeyObserver?
    private var observer: NSObjectProtocol?

    private var hover = HoverIntent(expandDelay: AppSettings.hoverDelay())
    private var ticker: Task<Void, Never>?
    private var shownPresentation = PillPresentation.collapsed
    private var shownLines = 1
    private var shownButtons = true

    init(model: CompanionModel) {
        self.model = model
    }

    func show() {
        geometry = Self.currentGeometry()
        let panel = NotchPanel(contentRect: geometry.collapsedFrame)
        panel.contentView = makeContentView()
        self.panel = panel
        applyVisibility(animated: false)
        observePresentation()

        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }

        // The "Show on" choice in the menu is a user default; move the pill when it points somewhere else.
        preferenceObserver = DefaultsKeyObserver(keys: [AppSettings.displayPreferenceKey, AppSettings.forceNotchlessKey, AppSettings.mascotSizeKey, AppSettings.hideWhenClosedKey]) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.applyVisibility(animated: true)
                if Self.currentGeometry() != self.geometry { self.reposition() }
            }
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
        panel.setFrame(geometry.frame(for: shownPresentation, attentionLines: shownLines, attentionButtons: shownButtons), display: true)
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
        if hover.isExpanded, !model.hoverExpanded { model.refreshUsage() }
        model.hoverExpanded = hover.isExpanded
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

    // MARK: Presentation

    /// Resizes the panel whenever the model asks for another presentation (hover, a permission prompt).
    private func observePresentation() {
        withObservationTracking {
            _ = model.presentation
            _ = model.isPillVisible
            _ = model.attentionLines
            _ = model.hasAttentionButtons
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.applyVisibility(animated: true)
                    self?.applyPresentation()
                    self?.observePresentation()
                }
            }
        }
    }

    private static let appearDuration = 0.5
    private static let disappearDuration = 0.4

    /// True while the pill is closing back into the notch (it can still be called back by a new session).
    private var closing = false

    private var presentedFrame: NSRect {
        geometry.frame(for: shownPresentation, attentionLines: shownLines, attentionButtons: shownButtons)
    }

    /// Shows the panel while Claude Code is open and takes it off the screen when it is not. The pill widens
    /// out of the notch on both sides and closes back into it. Where there is no notch to hide behind, the
    /// same movement is a narrow stub at the top center, with a fade.
    private func applyVisibility(animated: Bool) {
        guard let panel else { return }
        let visible = model.isPillVisible
        guard visible != panel.isVisible || (visible && closing) else { return }
        let resting = presentedFrame
        // On a notch screen the closed pill is hidden by the hardware notch itself; elsewhere it fades.
        let fades = !geometry.hasNotch
        if visible {
            closing = false
            guard animated else {
                panel.setFrame(resting, display: true)
                panel.alphaValue = 1
                panel.orderFrontRegardless()
                return
            }
            if !panel.isVisible {
                panel.alphaValue = fades ? 0 : 1
                panel.setFrame(geometry.closedFrame, display: true)
                panel.orderFrontRegardless()
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.appearDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrame(resting, display: true)
            }
        } else {
            hover.mouseExited(at: Date())
            model.hoverExpanded = false
            guard animated else { panel.orderOut(nil); return }
            closing = true
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = Self.disappearDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().alphaValue = fades ? 0 : 1
                panel.animator().setFrame(geometry.closedFrame, display: true)
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    // A new session during the closing took the pill back; it is already opening again.
                    guard let self, self.closing else { return }
                    self.closing = false
                    panel.orderOut(nil)
                    panel.alphaValue = 1
                    panel.setFrame(self.presentedFrame, display: false)
                }
            })
        }
    }

    private func applyPresentation() {
        guard let panel else { return }
        let target = model.presentation
        let lines = model.attentionLines
        let buttons = model.hasAttentionButtons
        let attentionChanged = target == .attention && (lines != shownLines || buttons != shownButtons)
        guard target != shownPresentation || attentionChanged else { return }
        shownPresentation = target
        shownLines = lines
        shownButtons = buttons
        let frame = geometry.frame(for: target, attentionLines: lines, attentionButtons: buttons)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    /// The screen the user chose in the menu (a notch screen by default, else the main one). The strip beside the
    /// notch is only as wide as the chosen mascot needs.
    private static func currentGeometry() -> NotchGeometry {
        let screens = ScreenInfo.connected()
        let strip = NotchGeometry.collapsedExtension(forMascotSize: CGFloat(AppSettings.mascotSize()))
        let chosen = DisplayChooser.choose(AppSettings.displayPreference(), from: screens)
        return (chosen ?? screens.first)?.geometry(collapsedExtension: strip)
            ?? NotchGeometry(screenFrame: .zero, safeAreaTop: 0, leftAreaWidth: nil, rightAreaWidth: nil)
    }
}
