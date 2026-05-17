cask "context-bar" do
  version "0.3.9"
  sha256 "73c6984d4a3a3d7c72d543a25eafad86d736d052fc9ceed8b2d938a8f464fac5"

  url "https://github.com/htahaozlu/context-bar/releases/download/v#{version}/ContextBar.dmg",
      verified: "github.com/htahaozlu/context-bar/"
  name "ContextBar"
  desc "Local-first repo context generator with a native macOS menubar companion"
  homepage "https://github.com/htahaozlu/context-bar"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates false
  depends_on macos: ">= :ventura"

  app "ContextBar.app"

  zap trash: [
    "~/.context-bar",
    "~/Library/Preferences/com.htahaozlu.contextbar.plist",
    "~/Library/Saved Application State/com.htahaozlu.contextbar.savedState",
  ]
end
