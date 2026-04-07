cask "privacy-shield" do
  version "0.0.6"
  sha256 "219e188889a4230dfeb049a25a9b8981b02bde8befd1ffac97e0a3c811279f6d"

  url "https://github.com/daliuchen/privacy-shield/releases/download/v0.0.6/PrivacyShield-macos.zip"
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
