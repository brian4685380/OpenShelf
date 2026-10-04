cask "openshelf" do
  version "0.7.0"
  sha256 "e59bbf91c759992a2dcd754b6fe550fd7c8863f0204a6d16a65cb8613f12f50e"

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
