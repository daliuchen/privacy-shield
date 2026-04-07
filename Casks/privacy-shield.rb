cask "privacy-shield" do
  version "0.0.5"
  sha256 "bce87661422ac7b68958e1697c8fa72faac78a4acffbbeb175df804ffcc97802"

  url "https://github.com/daliuchen/privacy-shield/releases/download/v0.0.5/PrivacyShield-macos.zip"
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
