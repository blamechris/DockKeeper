# Homebrew cask for DockKeeper (release checklist §7).
#
# Canonical copy; mirrored into blamechris/homebrew-tap at each release. The
# sha256 must come from Scripts/notarize.sh's final line (the stapled DMG) —
# package-dmg.sh's hash is pre-staple and will not match what users download.
# Submit to homebrew/cask central once notability requirements are met.
cask "dockkeeper" do
  version "0.9.3"
  sha256 "469f2ba134f68b749b2202d3f8c3ca0455040c9f23ae080fa23b10fa9e53c41d"

  url "https://github.com/blamechris/DockKeeper/releases/download/v#{version}/DockKeeper-#{version}.dmg"
  name "DockKeeper"
  desc "Keeps the macOS Dock on the edge and display you chose"
  homepage "https://github.com/blamechris/DockKeeper"

  app "DockKeeper.app"
  binary "dockkeeper"

  # Quit the running copy before the bundle is replaced. Without this, an upgrade
  # copies the new app over a live one, and the single-instance guard (DK-FR-012)
  # then makes the new copy stand down to the old one still in the menu bar — the
  # upgrade appears to do nothing.
  #
  # Scope, stated plainly: Homebrew dispatches the *installed* cask's uninstall
  # directives during an upgrade (`cask/upgrade.rb` loads `old_cask` via
  # `CaskLoader.load_from_installed_caskfile`), and 0.9.0/0.9.1 shipped no
  # `uninstall` stanza — so this takes effect for upgrades FROM 0.9.2 onward. The
  # 0.9.1 -> 0.9.2 upgrade was carried by `caveats` and the CHANGELOG instead.
  #
  # `quit:` sends a real Quit Apple Event, so the DK-FR-013 auto-hide restore runs
  # on the way out. `signal:` is the backstop for a copy that does not answer it:
  # TERM first, which ADR-013 routes through the same clean quit, then KILL for a
  # copy whose main queue is wedged and can process neither — an uncatchable exit
  # is covered by the persisted hide record and the launch repair, not from here.
  # `on_upgrade:` is mandatory, not decoration: Homebrew skips `signal:` on
  # upgrade and reinstall unless it is named
  # (`cask/artifact/uninstall.rb`, `UPGRADE_REINSTALL_SKIP_DIRECTIVES`).
  uninstall quit:       "com.dockkeeper.app",
            signal:     [
              ["TERM", "com.dockkeeper.app"],
              ["KILL", "com.dockkeeper.app"],
            ],
            on_upgrade: :signal

  # zap only — `brew uninstall --zap` / `brew zap`, never plain `brew uninstall`
  # (`installer.rb#uninstall` calls `uninstall_artifacts` and never reaches the
  # zap stanzas). The uninstall stanza above runs first, and `:quit`/`:signal`
  # are ordered before `:trash`, so a live copy restores Dock auto-hide and
  # clears the record before this removes it. If DockKeeper is NOT running with a
  # hide outstanding, this discards the record and a reinstall can no longer
  # repair the Dock automatically — Preferences ▸ Advanced ▸ Turn Off Dock
  # Auto-Hide still can, unconditionally. That is what zap means: user data goes.
  zap trash: [
    "~/Library/Logs/DockKeeper",
    "~/Library/Preferences/com.dockkeeper.app.plist",
    "~/Library/Saved Application State/com.dockkeeper.app.savedState",
  ]

  caveats <<~EOS
    Requires macOS 14 (Sonoma) or later.

    DockKeeper is free and open source (MIT), with no telemetry and no network
    use. Launch at Login is approved in System Settings › Login Items.

    Upgrading from 0.9.2 or later with Homebrew quits the running copy for you
    (the `uninstall quit:` stanza above). If you install by dragging the app out
    of the DMG instead, quit DockKeeper from its menu-bar icon first and open it
    again afterwards — a replaced app bundle is a new application to macOS, and
    DockKeeper's single-instance guard makes the new copy stand down while the
    old one is still live.

    Uninstalling does not remove DockKeeper's Login Items entry. Check
    System Settings › General › Login Items & Extensions if you remove the app.
  EOS
end
