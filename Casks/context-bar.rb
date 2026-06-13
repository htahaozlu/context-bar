cask "context-bar" do
  version "0.8.6"
  sha256 "a4aa9497ec324100cd11f37aafbfb23ae4d6f43c549932fab780ff2cc590777b"

  url "https://github.com/htahaozlu/context-bar/releases/download/v#{version}/ContextBar.dmg"
  name "ContextBar"
  desc "Usage and cost visibility for Claude Code and Codex — menubar app and CLI"
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
