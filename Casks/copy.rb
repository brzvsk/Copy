cask "copy" do
  version "0.1.0"
  # Fill this in at release time: shasum -a 256 Copy-#{version}.dmg
  sha256 "REPLACE_WITH_DMG_SHA256"

  url "https://github.com/tarikbc/Copy/releases/download/v#{version}/Copy-#{version}.dmg"
  name "Copy"
  desc "Visual shelf for your clipboard history"
  homepage "https://github.com/tarikbc/Copy"

  depends_on macos: ">= :sonoma"

  app "Copy.app"

  zap trash: [
    "~/Library/Application Support/Copy",
    "~/Library/Preferences/com.tarikbc.Copy.plist",
    "~/Library/Caches/com.tarikbc.Copy",
  ]
end
