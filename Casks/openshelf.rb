cask "openshelf" do
  version "0.7.0"
  sha256 "cc738abb2200bdedd169f9a0bf6c479781f5aa556e877849a288eb0c42aba564"

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
