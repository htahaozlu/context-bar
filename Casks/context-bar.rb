cask "context-bar" do
  version "0.8.1"
  sha256 "85d8d7288671a3a758b39ff2f7306518b6d6009750383687259f6f5168e06d72"

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
