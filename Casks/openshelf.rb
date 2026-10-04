cask "openshelf" do
  version "0.7.0"
  sha256 "1f2ea0062a753a8a0d869d8a381e698e9fdd634e04bb14c8f184536e7f998910"

  url "https://github.com/brian4685380/OpenShelf/releases/download/v#{version}/OpenShelf-v#{version}-macOS.zip"
  name "OpenShelf"
  desc "Lightweight file and content shelf"
  homepage "https://github.com/brian4685380/OpenShelf"

  depends_on arch: :arm64
  depends_on macos: :ventura

  app "OpenShelf.app"
  binary "#{appdir}/OpenShelf.app/Contents/MacOS/shelf", target: "shelf"

  uninstall quit: "com.brianyuan.OpenShelf"

  zap trash: "~/Library/Preferences/com.brianyuan.OpenShelf.plist"
end
