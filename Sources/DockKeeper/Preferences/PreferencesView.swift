import SwiftUI
import AppKit  // NSApplication.didBecomeActiveNotification
import DockKeeperCore

/// The Preferences window. v0.1 covers the General and Dock tabs; Advanced and
/// Support tabs are stubbed for later milestones.
struct PreferencesView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            DockTab()
                .tabItem { Label("Dock", systemImage: "dock.rectangle") }
            AdvancedTab()
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 420, height: 380)
    }
}

private struct AdvancedTab: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            Toggle("Verbose logging", isOn: $state.verboseLogging)
            Text("Extra detail in the system log (Console.app, subsystem com.dockkeeper.app).")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Toggle("Write a diagnostics file", isOn: $state.diagnosticsFileEnabled)
            Text("Off by default. Keeps a small local log of state changes and corrections (~1 MB, 7 days) you can attach to a bug report. Nothing ever leaves this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Reveal Diagnostics File") { state.revealDiagnosticsFile() }
                .disabled(!state.diagnosticsFileEnabled)

            Divider()

            Toggle("Keep windows in place when pinning", isOn: $state.preserveWindowLayout)
            Text("Off by default. Pinning the Dock to your preferred display can shift some windows to the other screen; turn this on to move them back afterward. This is the only feature that needs macOS Accessibility permission, and it's used solely to reposition your windows — nothing else does.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if state.preserveWindowLayout && !state.accessibilityGranted {
                HStack(spacing: 8) {
                    Text("Waiting for permission — windows won't move until Accessibility is granted.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Accessibility Settings") { state.openAccessibilitySettings() }
                        .font(.caption)
                }
            }

            Divider()

            Toggle("Global pause hotkey (⌃⌥⌘D)", isOn: $state.pauseHotkeyEnabled)
            Text("Off by default. When on, press ⌃⌥⌘D anywhere to pause or resume DockKeeper. Uses a system hot-key registration — no extra permission.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Toggle("Hide the Dock while screen sharing", isOn: $state.hideDockDuringScreenShare)
                .disabled(!state.screenCaptureAvailable)
            Text("Off by default. While a screen recording or share is running, DockKeeper turns on Dock auto-hide so the Dock stays out of the capture, then restores it when the share ends. If you already use Dock auto-hide, it's left untouched.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !state.screenCaptureAvailable {
                Text("Unavailable on this version of macOS — the screen-capture signal DockKeeper relies on isn't present, so this stays off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()

            Toggle("Keep a bottom Dock on my preferred display", isOn: $state.lockBottomDockToDisplay)
            Text("Off by default. With \u{201C}Displays have separate Spaces\u{201D} on, macOS gives a bottom Dock to whichever display you push the pointer to. DockKeeper can hold the pointer a few points clear of the bottom edge on your other displays, so the Dock is never called away — it does not move the Dock back, which macOS does not allow.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(state.bottomDockGuardCaption)
                .font(.caption)
                .foregroundStyle(.secondary)

            // DK-FR-013 S11 — the permanent home of the manual recovery.
            // Unconditional (only gated on CoreDock resolving), because the
            // users who need it most are the ones whose record was never
            // written: a build that predates it, a wiped preferences domain, a
            // power loss. Deliberately not disabled on the toggle.
            // Labelled to match the menu item exactly: "restore auto-hide" reads
            // cold as restoring it *to on*, and ADR-013 leans on this control
            // being plainly labelled to justify making it unconditional.
            Button("Turn Off Dock Auto-Hide") { state.restoreDockAutoHide() }
                .disabled(!state.coreDockAutoHideAvailable)
            Text("Turns macOS Dock auto-hide off. Use this if a screen share ended "
                 + "unexpectedly and your Dock is still hiding itself.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .onAppear { state.refreshAccessibilityStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.refreshAccessibilityStatus()
        }
    }
}

private struct GeneralTab: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            Toggle("Enable DockKeeper", isOn: $state.isEnabled)
            Text("When enabled, DockKeeper keeps the Dock locked to your chosen edge.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Toggle("Launch at Login", isOn: $state.launchAtLogin)
            if let message = state.loginItemMessage {
                HStack(spacing: 8) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Login Items…") { state.openLoginItemsSettings() }
                        .font(.caption)
                }
            }
        }
        .padding()
    }
}

private struct DockTab: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            Picker("Lock Edge", selection: $state.lockEdge) {
                ForEach(DockOrientation.userSelectable, id: \.self) { edge in
                    Text(edge.displayName).tag(edge)
                }
            }
            .pickerStyle(.segmented)

            Text("DockKeeper automatically restores the Dock after sleep, wake, and display changes while enabled.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
