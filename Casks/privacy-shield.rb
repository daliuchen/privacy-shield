cask "privacy-shield" do
  version "0.0.3"
  sha256 "59bf887bbcfa53062366782e85c7e6928ced38644288ff06b07004f53be4bc19"

  url "https://github.com/daliuchen/privacy-shield/releases/download/v#{version}/PrivacyShield-macos.zip"
  name "Privacy Shield"
  desc "macOS menu bar app that covers all displays with a privacy overlay"
  homepage "https://github.com/daliuchen/privacy-shield"

  app "Privacy Shield.app"

  zap trash: [
    "~/Library/Preferences/com.daliuchen.privacyshield.plist",
  ]
end
