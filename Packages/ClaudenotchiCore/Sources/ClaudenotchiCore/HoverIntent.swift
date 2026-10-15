import Foundation

/// Decides when the pill is expanded, from mouse enter/exit events and a clock.
/// Pure and clock-free: the caller passes `now`, so tests never wait.
public struct HoverIntent: Equatable, Sendable {
    /// Seconds the mouse must rest on the pill before it expands. Negative turns hover expansion off.
    public var expandDelay: TimeInterval
    /// Seconds the pill stays expanded after the mouse leaves, so a slightly shaky exit does not flicker.
    public var collapseGrace: TimeInterval

    public private(set) var isExpanded = false

    private var enteredAt: Date?
    private var leftAt: Date?

    public init(expandDelay: TimeInterval, collapseGrace: TimeInterval = 0.25) {
        self.expandDelay = expandDelay
        self.collapseGrace = collapseGrace
    }

    /// Whether the caller still needs to call `tick(now:)` (a wait or a grace period is running).
    public var needsTicks: Bool { enteredAt != nil || isExpanded }

    public mutating func mouseEntered(at now: Date) {
        leftAt = nil
        if enteredAt == nil { enteredAt = now }
    }

    public mutating func mouseExited(at now: Date) {
        guard enteredAt != nil else { return }
        enteredAt = nil
        if isExpanded { leftAt = now }
    }

    public mutating func tick(now: Date) {
        if expandDelay < 0 {
            isExpanded = false
            leftAt = nil
            return
        }
        if let entered = enteredAt {
            if !isExpanded, now >= entered.addingTimeInterval(expandDelay) { isExpanded = true }
        } else if isExpanded, let left = leftAt, now >= left.addingTimeInterval(collapseGrace) {
            isExpanded = false
            leftAt = nil
        }
    }
}
