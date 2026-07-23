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

        Toggle("Auto Recover", isOn: $state.autoRecover)

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
