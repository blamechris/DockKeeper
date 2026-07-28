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

  zap trash: [
    "~/Library/Logs/DockKeeper",
  ]

  caveats <<~EOS
    Requires macOS 14 (Sonoma) or later.

    DockKeeper is free and open source (MIT), with no telemetry and no network
    use. Launch at Login is approved in System Settings › Login Items.
  EOS
end
