import SwiftUI
import DockKeeperCore

/// The dropdown shown from the menu-bar icon.
struct MenuBarContent: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Toggle("Enabled", isOn: $state.isEnabled)

        Divider()

        Menu("Lock Edge") {
            ForEach(DockOrientation.userSelectable, id: \.self) { edge in
                Button {
                    state.lock(to: edge)
                } label: {
                    HStack {
                        Text(edge.displayName)
                        if state.lockEdge == edge { Image(systemName: "checkmark") }
                    }
                }
            }
        }

        Menu("Preferred Display") {
            Button {
                state.setPreferredDisplay(nil)
            } label: {
                HStack {
                    Text("Any (don't pin)")
                    if !state.hasPreferredDisplay { Image(systemName: "checkmark") }
                }
            }
            if state.displays.count > 1 {
                Divider()
                ForEach(state.displays) { display in
                    Button {
                        state.setPreferredDisplay(display)
                    } label: {
                        HStack {
                            Text(display.name)
                            if state.preferredDisplaySelectionID == display.id { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
        }

        Divider()

        Toggle("Launch at Login", isOn: $state.launchAtLogin)

        if let message = state.statusMessage ?? state.lastPinMessage ?? state.loginItemMessage {
            Divider()
            Text(message)
            if state.loginItemMessage != nil {
                Button("Open Login Items…") { state.openLoginItemsSettings() }
            }
        }

        Divider()

        Button("Preferences…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",")

        Button("Support Development") {
            if let url = URL(string: "https://github.com/blamechris/DockKeeper") {
                NSWorkspace.shared.open(url)
            }
        }

        Divider()

        Button("Quit DockKeeper") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
