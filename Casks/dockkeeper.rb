# Homebrew cask for DockKeeper (release checklist §7).
#
# Canonical copy; mirrored into blamechris/homebrew-tap at each release. The
# sha256 must come from Scripts/notarize.sh's final line (the stapled DMG) —
# package-dmg.sh's hash is pre-staple and will not match what users download.
# Submit to homebrew/cask central once notability requirements are met.
cask "dockkeeper" do
  version "0.9.0"
  sha256 "2639f68329939b5606d1f5b5799e9017f8e7c4d3eaca7ed3f6a3c6b3536c6137"

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
