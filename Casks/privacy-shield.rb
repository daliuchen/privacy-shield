cask "privacy-shield" do
  version "0.0.4"
  sha256 "6e2b9ebd722ae0e632fdf692b725d32d990fbb00f9e7a80bbbbebb735f6be7e1"

  url "https://github.com/daliuchen/privacy-shield/releases/download/v0.0.4/PrivacyShield-macos.zip"
  name "Privacy Shield"
  desc "macOS menu bar app that covers all displays with a privacy overlay"
  homepage "https://github.com/daliuchen/privacy-shield"

  app "Privacy Shield.app"

  zap trash: [
    "~/Library/Preferences/com.daliuchen.privacyshield.plist",
  ]
end
