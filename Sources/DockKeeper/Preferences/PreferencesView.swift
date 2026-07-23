import SwiftUI
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
        }
        .frame(width: 420, height: 260)
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

            Toggle("Auto Recover", isOn: $state.autoRecover)
            Text("Automatically restore the Dock after sleep, wake, and display changes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
