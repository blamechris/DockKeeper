import AppKit
import Carbon.HIToolbox
import DockKeeperCore

/// Thin wrapper over Carbon's `RegisterEventHotKey` for the optional global
/// pause hotkey (DK-FR-009). Carbon's hot-key API is public and grants a
/// system-wide key with **zero permissions** — the zero-permission posture
/// (TDD §10) holds. Registered only while the setting is on; off by default so
/// nothing is captured system-wide unless the user asks (kickoff rule 20).
///
/// The combo is fixed at ⌃⌥⌘D for now; user-customization is future work.
/// Runs on the main actor because it mutates AppKit-adjacent Carbon state and
/// drives main-actor UI through `onHotKey`. Callers must pair `start()`/
/// `stop()` — the C handler holds an unretained reference to this object.
@MainActor
final class HotKeyCenter {

    /// Invoked on the main actor each time the hot key is pressed.
    var onHotKey: (() -> Void)?

    /// Human-readable combo for UI captions.
    static let comboDescription = "⌃⌥⌘D"

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    // Fixed combo: control+option+command + D.
    private let keyCode = UInt32(kVK_ANSI_D)
    private let modifiers = UInt32(cmdKey | optionKey | controlKey)
    // "DKEP" four-char signature namespaces our registration.
    private let hotKeyID = EventHotKeyID(signature: 0x444B_4550, id: 1)

    /// Register the hot key and its handler. Idempotent; logs and stays off on
    /// failure (e.g. the combo is already claimed) rather than trapping.
    func start() {
        guard handlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            Self.hotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard installStatus == noErr else {
            Log.app.error("Pause hotkey: handler install failed (status \(installStatus, privacy: .public))")
            handlerRef = nil
            return
        }

        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        if registerStatus != noErr {
            Log.app.error("Pause hotkey: registration failed (status \(registerStatus, privacy: .public))")
            stop()
        }
    }

    /// Unregister the hot key and remove the handler. Safe to call repeatedly.
    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    deinit {
        // Carbon refs are torn down in stop(), which the owner pairs with
        // start(); deinit is nonisolated and cannot touch main-actor state.
        // Process exit releases anything still registered.
    }

    /// C-callable trampoline: recover the instance from userData and hop to the
    /// main actor (mirrors DockMonitor's `Unmanaged` CG-callback pattern).
    private static let hotKeyHandler: EventHandlerUPP = { _, _, userData in
        guard let userData else { return OSStatus(eventNotHandledErr) }
        let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
        Task { @MainActor in
            center.onHotKey?()
        }
        return noErr
    }
}
