cask "openshelf" do
  version "0.9.0"
  sha256 "864687b6b9108a8bde2145963e46f38836500658f1cd458a106d1b0a705fcd51"

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
