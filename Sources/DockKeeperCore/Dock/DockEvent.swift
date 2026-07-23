import Foundation

/// The typed events that can require Dock reconciliation (TDD §8.1).
///
/// `DockMonitor` emits these; `RecoveryCoordinator` is their single consumer.
/// Plain values so coordinator logic is testable by feeding synthetic
/// sequences.
public enum DockEvent: String, Sendable, Equatable, CaseIterable {
    /// App launched or the user enabled DockKeeper — full reconcile.
    case enabled
    /// `NSWorkspace.didWakeNotification`.
    case wake
    /// `NSWorkspace.screensDidWakeNotification`.
    case screensWake
    /// `CGDisplayRegisterReconfigurationCallback` (completed changes only).
    case displayReconfigured
    /// `NSApplication.didChangeScreenParametersNotification`.
    case screenParametersChanged
    /// `NSWorkspace.activeSpaceDidChangeNotification` — cheap edge check only.
    case spaceChanged
    /// `NSWorkspace.sessionDidBecomeActiveNotification` (fast user switching).
    case sessionBecameActive
    /// `UserDefaults.didChangeNotification` — settings possibly edited by the
    /// CLI while the app runs (DK-FR-007-S3).
    case settingsChanged
    /// Safety-net poll tick (ADR-005).
    case pollTick

    /// Space changes only ever need the (cheap) edge check; everything else
    /// reconciles edge + pin (TDD §8.1).
    public var reconcilesPinning: Bool {
        switch self {
        case .spaceChanged, .pollTick: return false
        default: return true
        }
    }

    /// Display-reconfiguration events can be echoes of DockKeeper's own pin
    /// (a pin *is* a reconfiguration); only these are echo-suppressed.
    public var canBeSelfInflictedEcho: Bool {
        switch self {
        case .displayReconfigured, .screenParametersChanged: return true
        default: return false
        }
    }
}
