# Homebrew cask for DockKeeper (release checklist §7).
#
# Canonical copy; mirrored into blamechris/homebrew-tap at each release
# (version + sha256 come from Scripts/package-dmg.sh output). Submit to
# homebrew/cask central once notability requirements are met.
cask "dockkeeper" do
  version "0.9.0"
  sha256 "c9a37ed11d523aa11567664a8c281feccea8342f9c9fb27407758579ccff41f6"

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
