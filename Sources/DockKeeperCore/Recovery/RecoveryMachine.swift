import Foundation
import CoreGraphics

/// The application states from the technical design (§5.1). `paused` is a
/// planned affordance ("Pause for 1 hour") — declared for completeness, not
/// yet reachable in v1 code paths.
public enum RecoveryState: Sendable, Equatable {
    case disabled
    case starting
    case monitoring
    case restoring
    case preferredDisplayMissing
    case degraded
    case paused
    case error(ErrorReason)

    public enum ErrorReason: String, Sendable {
        /// The cooldown budget tripped: something keeps fighting our corrections.
        case oscillation
        /// The retry ladder was exhausted without convergence.
        case notConverging
    }

    /// SF Symbol for the menu-bar icon, so each state is visually distinct
    /// (M1; TDD open question #8).
    public var menuSymbolName: String {
        switch self {
        case .disabled:
            return "rectangle.dashed"
        case .paused:
            return "pause.rectangle"
        case .degraded, .error:
            return "exclamationmark.triangle"
        case .starting, .monitoring, .restoring, .preferredDisplayMissing:
            return "dock.rectangle"
        }
    }

    /// Short user-facing note for the menu; `nil` when nothing needs saying.
    public var userMessage: String? {
        switch self {
        case .disabled, .starting, .monitoring, .restoring, .paused:
            return nil
        case .preferredDisplayMissing:
            return "Your preferred display isn't connected."
        case .degraded:
            return "Running degraded: the live Dock mechanism is unavailable, "
                + "so corrections restart the Dock."
        case .error(.oscillation):
            return "Paused corrections: something else keeps moving the Dock. "
                + "Will retry on the next display or wake event."
        case .error(.notConverging):
            return "Couldn't restore the Dock after several attempts. "
                + "Will retry on the next display or wake event."
        }
    }
}

/// Everything a reconcile pass needs to decide, captured as a value so the
/// decision is pure (TDD §8.3 `decide`) and testable without hardware.
public struct ReconcileInput: Sendable, Equatable {
    /// The Dock's observed edge; `nil` means unreadable → treated as drift.
    public var currentEdge: DockOrientation?
    public var desiredEdge: DockOrientation
    /// False when the flicker-free primary mechanism (CoreDock) is unavailable.
    public var primaryMechanismAvailable: Bool
    /// False while the display topology looks mid-transition (e.g. no displays
    /// enumerated right after wake) — retry instead of acting on garbage.
    public var displaysReady: Bool
    /// Whether this pass should reconcile pinning at all (space-change and
    /// poll events are edge-only — TDD §8.1).
    public var includesPinning: Bool
    /// The pure pinning decision for the current snapshot.
    public var pinDecision: PinDecision

    public enum PinDecision: Sendable, Equatable {
        case terminal(PinOutcome)
        case reconfigure(CGDirectDisplayID)
    }

    public init(
        currentEdge: DockOrientation?,
        desiredEdge: DockOrientation,
        primaryMechanismAvailable: Bool = true,
        displaysReady: Bool = true,
        includesPinning: Bool = true,
        pinDecision: PinDecision = .terminal(.noPreference)
    ) {
        self.currentEdge = currentEdge
        self.desiredEdge = desiredEdge
        self.primaryMechanismAvailable = primaryMechanismAvailable
        self.displaysReady = displaysReady
        self.includesPinning = includesPinning
        self.pinDecision = pinDecision
    }
}

/// A concrete correction the coordinator must perform.
public enum RecoveryEffect: Sendable, Equatable {
    case setEdge(DockOrientation)
    case pin(CGDirectDisplayID)
}

/// What one reconcile pass concluded.
public struct PassResult: Sendable, Equatable {
    /// Corrections to apply now (empty when converged, retrying, or erroring).
    public var effects: [RecoveryEffect]
    /// When non-nil, schedule another pass after this many seconds (the retry
    /// ladder verifying convergence, or a displays-not-ready retry).
    public var nextPassDelay: TimeInterval?
    /// Machine state after this pass.
    public var state: RecoveryState
}

/// The pure, synchronous core of recovery (TDD §8.3): debounce scheduling and
/// effect execution live in `RecoveryCoordinator`; every *decision* — echo
/// suppression, the retry ladder, the cooldown budget, steady-state derivation
/// — lives here, where it is unit-testable with a simulated clock.
public struct RecoveryMachine: Sendable {

    public struct Config: Sendable {
        /// Coalescing window for event bursts (TDD §8.4; `Settings.restoreDelay`).
        public var debounce: TimeInterval
        /// Pre-pass delays: pass 0 runs after `debounce`, pass n>0 after
        /// `retryLadder[min(n, count-1)]`. Passes beyond the ladder are
        /// exhaustion (TDD §8.4: 0 s, +1.5 s, +4 s).
        public var retryLadder: [TimeInterval]
        /// Self-inflicted display-reconfiguration events within this window of
        /// a pin are swallowed (TDD §8.3).
        public var echoWindow: TimeInterval
        /// More than `cooldownBudget` correcting passes within
        /// `cooldownWindow` seconds → `error(.oscillation)` (TDD §8.4).
        public var cooldownBudget: Int
        public var cooldownWindow: TimeInterval

        public init(
            debounce: TimeInterval = 0.4,
            retryLadder: [TimeInterval] = [0, 1.5, 4.0],
            echoWindow: TimeInterval = 2.0,
            cooldownBudget: Int = 6,
            cooldownWindow: TimeInterval = 60
        ) {
            self.debounce = debounce
            self.retryLadder = retryLadder
            self.echoWindow = echoWindow
            self.cooldownBudget = cooldownBudget
            self.cooldownWindow = cooldownWindow
        }
    }

    public let config: Config
    public private(set) var state: RecoveryState
    private var correctionTimestamps: [Date] = []
    private var lastSelfInflictedPin: Date?

    public init(config: Config = Config(), state: RecoveryState = .disabled) {
        self.config = config
        self.state = state
    }

    /// Highest valid pass index: the ladder's passes apply corrections; one
    /// final index beyond it is a check-only verification pass.
    private var finalPassIndex: Int { config.retryLadder.count }

    /// Pre-pass delay for pass `index` (index ≥ 1; pass 0 is debounced).
    public func delayForPass(_ index: Int) -> TimeInterval {
        guard !config.retryLadder.isEmpty else { return 0 }
        return config.retryLadder[min(index, config.retryLadder.count - 1)]
    }

    // MARK: - Transitions driven from outside

    public mutating func noteEnabled() {
        state = .starting
    }

    public mutating func noteDisabled() {
        state = .disabled
        correctionTimestamps.removeAll()
        lastSelfInflictedPin = nil
    }

    /// Record that DockKeeper itself just reconfigured displays (a pin), so
    /// the resulting reconfiguration event can be recognized as an echo.
    public mutating func notePinApplied(now: Date) {
        lastSelfInflictedPin = now
    }

    // MARK: - Event admission (echo suppression, disabled gate)

    /// Whether `event` should schedule a reconcile at all.
    public func shouldProcess(_ event: DockEvent, now: Date) -> Bool {
        if state == .disabled || state == .paused { return false }
        if event.canBeSelfInflictedEcho,
           let pin = lastSelfInflictedPin,
           now.timeIntervalSince(pin) < config.echoWindow {
            return false
        }
        return true
    }

    // MARK: - The reconcile pass (pure)

    public mutating func reconcile(passIndex: Int, input: ReconcileInput, now: Date) -> PassResult {
        guard state != .disabled, state != .paused else {
            return PassResult(effects: [], nextPassDelay: nil, state: state)
        }

        // Mid-transition topology (e.g. wake before displays are ready):
        // don't act on garbage — climb the ladder and look again.
        guard input.displaysReady else {
            if passIndex < finalPassIndex {
                state = .restoring
                return PassResult(effects: [], nextPassDelay: delayForPass(passIndex + 1), state: state)
            }
            state = .error(.notConverging)
            return PassResult(effects: [], nextPassDelay: nil, state: state)
        }

        let effects = Self.decide(input: input)

        if effects.isEmpty {
            state = steadyState(for: input)
            return PassResult(effects: [], nextPassDelay: nil, state: state)
        }

        pruneCorrections(now: now)
        if correctionTimestamps.count >= config.cooldownBudget {
            state = .error(.oscillation)
            return PassResult(effects: [], nextPassDelay: nil, state: state)
        }

        // Ladder exhausted: we've applied `retryLadder.count` times and drift
        // is still there — stop fighting until the next event (check-only).
        if passIndex >= finalPassIndex {
            state = .error(.notConverging)
            return PassResult(effects: [], nextPassDelay: nil, state: state)
        }

        correctionTimestamps.append(now)
        state = .restoring
        return PassResult(effects: effects, nextPassDelay: delayForPass(passIndex + 1), state: state)
    }

    /// TDD §8.3 `decide(snapshot, settings) -> [Action]` — pure.
    public static func decide(input: ReconcileInput) -> [RecoveryEffect] {
        var effects: [RecoveryEffect] = []
        if input.currentEdge != input.desiredEdge {
            effects.append(.setEdge(input.desiredEdge))
        }
        if input.includesPinning, case .reconfigure(let displayID) = input.pinDecision {
            effects.append(.pin(displayID))
        }
        return effects
    }

    // MARK: - Steady-state derivation

    private func steadyState(for input: ReconcileInput) -> RecoveryState {
        if !input.primaryMechanismAvailable { return .degraded }
        if input.includesPinning {
            if case .terminal(.displayNotConnected) = input.pinDecision {
                return .preferredDisplayMissing
            }
            return .monitoring
        }
        // Edge-only pass: it can't learn anything about the preferred display,
        // so don't overwrite a standing preferredDisplayMissing.
        return state == .preferredDisplayMissing ? .preferredDisplayMissing : .monitoring
    }

    private mutating func pruneCorrections(now: Date) {
        let window = config.cooldownWindow
        correctionTimestamps.removeAll { now.timeIntervalSince($0) > window }
    }
}
