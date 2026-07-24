# Homebrew cask for DockKeeper (release checklist §7).
#
# Not yet submitted anywhere: at first release, fill in version + sha256 (from
# Scripts/package-dmg.sh output), then either host in a personal tap
# (blamechris/homebrew-tap) or submit to homebrew/cask once notability
# requirements are met. `brew install --cask dockkeeper` must be verified
# end-to-end, including the CLI symlink, before the release ships.
cask "dockkeeper" do
  version "1.0.0" # placeholder — set at release
  sha256 "PLACEHOLDER_SHA256_FROM_PACKAGE_DMG"

  url "https://github.com/blamechris/DockKeeper/releases/download/v#{version}/DockKeeper-#{version}.dmg"
  name "DockKeeper"
  desc "Keeps the macOS Dock on the edge and display you chose"
  homepage "https://github.com/blamechris/DockKeeper"

  depends_on macos: ">= :sonoma"

  app "DockKeeper.app"
  binary "dockkeeper"

  zap trash: [
    "~/Library/Logs/DockKeeper",
  ]

  caveats <<~EOS
    DockKeeper is free and open source (MIT), with no telemetry and no network
    use. Launch at Login is approved in System Settings › Login Items.
  EOS
end
