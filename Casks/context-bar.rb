cask "context-bar" do
  version "0.3.13"
  sha256 "87d52391de8d59545b3ed5d1db152237da6f8f84f74cda48332823b7ec0af20a"

  url "https://github.com/htahaozlu/context-bar/releases/download/v#{version}/ContextBar.dmg"
  name "ContextBar"
  desc "Local-first repo context generator with a native menubar companion"
  homepage "https://github.com/htahaozlu/context-bar"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates false
  depends_on macos: :ventura

  app "ContextBar.app"

  zap trash: [
    "~/.context-bar",
    "~/Library/Preferences/com.htahaozlu.contextbar.plist",
    "~/Library/Saved Application State/com.htahaozlu.contextbar.savedState",
  ]
end
