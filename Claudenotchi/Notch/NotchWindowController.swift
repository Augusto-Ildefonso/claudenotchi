import AppKit
import SwiftUI

/// Owns the notch panel and keeps it aligned with the screen's notch.
final class NotchWindowController {
    private let model: CompanionModel
    private var panel: NotchPanel?
    private var observer: NSObjectProtocol?

    init(model: CompanionModel) {
        self.model = model
    }

    func show() {
        let geometry = Self.currentGeometry()
        let panel = NotchPanel(contentRect: geometry.collapsedFrame)
        panel.contentView = NSHostingView(rootView: PillView(geometry: geometry, model: model))
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

    private func reposition() {
        guard let panel else { return }
        let geometry = Self.currentGeometry()
        panel.contentView = NSHostingView(rootView: PillView(geometry: geometry, model: model))
        panel.setFrame(geometry.collapsedFrame, display: true)
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
