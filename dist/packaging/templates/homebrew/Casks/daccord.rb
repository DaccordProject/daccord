# Review only: publication requires a DMG built with PACKAGE_MANAGER=true.
# Do not place updater markers inside the signed Daccord.app bundle.
cask "daccord" do
  version "@@VERSION@@"
  sha256 "@@MACOS_SHA256@@"

  url "https://github.com/DaccordProject/daccord/releases/download/v#{version}/@@MACOS_ASSET@@"
  name "Daccord"
  desc "Chat, voice, video, and screen sharing for Daccord communities"
  homepage "https://github.com/DaccordProject/daccord"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :catalina"
  app "Daccord.app"

  uninstall quit: "com.cattrall.daccord"

  # Never delete Documents/daccord/data: it contains accounts and messages.
  zap trash: "~/Library/Caches/com.cattrall.daccord"
end
