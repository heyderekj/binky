cask "binky" do
  version "1.7.0"
  # Refresh this checksum when publishing `Binky-{version}.zip` via `./release.sh`
  # (a local ad-hoc build can produce a different hash than the signed release artifact).
  sha256 "aed9d3ce0c599f9f19122955d0ab15780cedc1238c1c7a8ab2f73524fe613858"

  url "https://github.com/heyderekj/binky/releases/download/v#{version}/Binky-#{version}.zip"
  name "Binky"
  desc "Downloads inbox organizer — sort, route, tag, and review files"
  homepage "https://binkyfiles.com/"

  depends_on macos: :sonoma

  app "Binky.app"
end
