# Homebrew cask for DockKeeper (release checklist §7).
#
# Canonical copy; mirrored into blamechris/homebrew-tap at each release. The
# sha256 must come from Scripts/notarize.sh's final line (the stapled DMG) —
# package-dmg.sh's hash is pre-staple and will not match what users download.
# Submit to homebrew/cask central once notability requirements are met.
cask "dockkeeper" do
  version "0.9.1"
  sha256 "ed7bad6bf14d4a7c29b437728d99e5ddde84300327dc2ab8cf46696604cc34d2"

  url "https://github.com/blamechris/DockKeeper/releases/download/v#{version}/DockKeeper-#{version}.dmg"
  name "DockKeeper"
  desc "Keeps the macOS Dock on the edge and display you chose"
  homepage "https://github.com/blamechris/DockKeeper"

  app "DockKeeper.app"
  binary "dockkeeper"

  # Quit the running copy before the bundle is replaced. Without this an upgrade
  # copies the new app over a live one, and the single-instance guard (DK-FR-012)
  # then makes the new copy stand down to the old one that is still in the menu
  # bar — the upgrade appears to do nothing. `quit:` sends a real Quit Apple
  # Event, so the DK-FR-013 auto-hide restore runs on the way out; `signal:` is
  # the backstop for a copy that does not answer it.
  uninstall quit:   "com.dockkeeper.app",
            signal: ["TERM", "com.dockkeeper.app"]

  # The preferences domain carries the screen-share hide record (DK-FR-013).
  # Leaving it behind on `brew uninstall` would strand Dock auto-hide on with the
  # only app that could repair it removed.
  zap trash: [
    "~/Library/Logs/DockKeeper",
    "~/Library/Preferences/com.dockkeeper.app.plist",
    "~/Library/Saved Application State/com.dockkeeper.app.savedState",
  ]

  caveats <<~EOS
    Requires macOS 14 (Sonoma) or later.

    DockKeeper is free and open source (MIT), with no telemetry and no network
    use. Launch at Login is approved in System Settings › Login Items.

    If DockKeeper is already running when you upgrade, quit it from its menu-bar
    icon and open it again — a replaced app bundle is a new application to macOS,
    and DockKeeper's single-instance guard makes the new copy stand down while the
    old one is still live.

    Uninstalling does not remove DockKeeper's Login Items entry. Check
    System Settings › General › Login Items & Extensions if you remove the app.
  EOS
end
