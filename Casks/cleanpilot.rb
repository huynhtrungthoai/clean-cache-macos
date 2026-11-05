# Documentation: https://github.com/huynhtrungthoai/clean-cache-macos/blob/main/docs/homebrew.md
cask "cleanpilot" do
  version "1.0"
  # Set this to the SHA256 that `RELEASE=1 NOTARIZE=1 ARCH=universal bash build_app/build.sh`
  # prints for the DMG uploaded to the v#{version} release. Never use `:no_check`:
  # the pinned hash is what stops a swapped download from being installed.
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/huynhtrungthoai/clean-cache-macos/releases/download/v#{version}/CleanPilot-#{version}-universal.dmg"
  name "CleanPilot"
  desc "Disk cleaner that only ever moves files to the Trash"
  homepage "https://github.com/huynhtrungthoai/clean-cache-macos"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :ventura

  app "CleanPilot.app"
  # Agent CLI + stdio MCP server bundled inside the app
  binary "#{appdir}/CleanPilot.app/Contents/MacOS/diskwise"

  uninstall quit: "com.huynhtrungthoai.cleanpilot"

  zap trash: [
    "~/Library/Application Support/DiskWise/agent",
    "~/Library/Caches/com.huynhtrungthoai.cleanpilot",
    "~/Library/Preferences/com.huynhtrungthoai.cleanpilot.plist",
    "~/Library/Saved Application State/com.huynhtrungthoai.cleanpilot.savedState",
  ]
end
