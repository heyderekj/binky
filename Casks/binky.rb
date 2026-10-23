cask "binky" do
  version "1.6.0"
  # Refresh this checksum when publishing `Binky-{version}.zip` via `./release.sh`
  # (a local ad-hoc build can produce a different hash than the signed release artifact).
  sha256 "43a4d44fc7d54b718b6c6728168984dadbed07d7fd3c0b8fae469329c35f5b30"

  url "https://github.com/heyderekj/binky/releases/download/v#{version}/Binky-#{version}.zip"
  name "Binky"
  desc "Downloads inbox organizer — sort, route, tag, and review files"
  homepage "https://binkyfiles.com/"

  depends_on macos: :sonoma

  app "Binky.app"
end
