cask "privacy-shield" do
  version "0.0.7"
  sha256 "784b2d8fbf864b931124365a5419b303b915ffb5cd0a938e2dd7ccbd2b9f0d86"

  url "https://github.com/daliuchen/privacy-shield/releases/download/v0.0.7/PrivacyShield-macos.zip"
  name "Privacy Shield"
  desc "macOS menu bar app that covers all displays with a privacy overlay"
  homepage "https://github.com/daliuchen/privacy-shield"

  app "Privacy Shield.app"

  caveats <<~EOS
    Privacy Shield is ad-hoc signed and not notarized by Apple.
    macOS Gatekeeper may block the first launch. To fix, run:

      xattr -cr "/Applications/Privacy Shield.app"
  EOS

  zap trash: [
    "~/Library/Preferences/com.daliuchen.privacyshield.plist",
  ]
end
