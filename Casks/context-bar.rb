cask "context-bar" do
  version "0.3.24"
  sha256 "98dacc92228cea2349df71d659934b015e0165b51f4de528d30e419c32daae65"

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
