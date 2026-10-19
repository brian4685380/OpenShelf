cask "openshelf" do
  version "0.8.1"
  sha256 "1a1d82f287543f1128f21f9a2f3bb6f1985f2e0c0a40a0b624e090fb1350e31f"

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
