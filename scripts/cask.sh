#!/bin/bash
# Prints the Homebrew cask for a release, for the mohitkyadav/homebrew-tap repo.
#
#   scripts/cask.sh <version> <sha256>
set -euo pipefail

version=${1:?usage: scripts/cask.sh <version> <sha256>}
sha256=${2:?usage: scripts/cask.sh <version> <sha256>}

cat <<EOF
cask "scope" do
  version "$version"
  sha256 "$sha256"

  url "https://github.com/mohitkyadav/scope/releases/download/v#{version}/Scope-#{version}.zip"
  name "Scope"
  desc "Screen recorder with automatic zoom, smooth cursor and webcam bubble"
  homepage "https://github.com/mohitkyadav/scope"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sequoia

  app "Scope.app"

  # Scope isn't notarized by Apple, so clear the quarantine flag that would stop it opening.
  postflight_steps do
    run "/usr/bin/xattr",
        args:           ["-dr", "com.apple.quarantine", "{{appdir}}/Scope.app"],
        writable_paths: "Scope.app",
        writable_base:  :appdir
  end

  zap trash: [
    "~/Library/Application Scripts/com.only4.Scope",
    "~/Library/Containers/com.only4.Scope",
  ]
end
EOF
