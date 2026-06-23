cask "openshelf" do
  version "0.3.0"
  sha256 :no_check

  url "https://github.com/brian4685380/OpenShelf/releases/download/v#{version}/OpenShelf-v#{version}-macOS.zip"
  name "OpenShelf"
  desc "Lightweight file shelf for macOS"
  homepage "https://github.com/brian4685380/OpenShelf"

  depends_on macos: :ventura

  app "OpenShelf.app"
  binary "#{appdir}/OpenShelf.app/Contents/MacOS/shelf", target: "shelf"

  uninstall quit: "com.brianyuan.OpenShelf"

  zap trash: [
    "~/Library/Preferences/com.brianyuan.OpenShelf.plist",
  ]
end
