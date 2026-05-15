cask "context-hud" do
  version "0.2.2"
  sha256 "e5e15f741c909da41d474049f6afcbd164704cd06f4c635f6f18711f9acbf29e"

  url "https://github.com/htahaozlu/context-hud/releases/download/v#{version}/ContextHUD.dmg",
      verified: "github.com/htahaozlu/context-hud/"
  name "ContextHUD"
  desc "Local-first repo context generator with a native macOS menubar companion"
  homepage "https://github.com/htahaozlu/context-hud"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates false
  depends_on macos: ">= :ventura"

  app "ContextHUD.app"

  zap trash: [
    "~/.context-hud",
    "~/Library/Preferences/com.htahaozlu.contexthud.plist",
    "~/Library/Saved Application State/com.htahaozlu.contexthud.savedState",
  ]
end
