#!/usr/bin/env bash
# Release CI: attaches the DMG to the v<version> release that `changeset publish` created,
# then publishes the Sparkle appcast. The app reads the appcast from the "appcast"
# pre-release (never "latest"), and it only changes once this release's DMG is uploaded,
# so installed copies never see an update they can't download.
#
#   scripts/release/publish.sh 1.3.0
set -euo pipefail
cd "$(dirname "$0")/../.."
version="${1:?usage: scripts/release/publish.sh <version>}"

gh release upload "v$version" "build/Haul-$version.dmg"
gh release view appcast >/dev/null 2>&1 ||
    gh release create appcast --prerelease --title "Update feed" --notes "Sparkle appcast for in-app updates."
gh release upload appcast build/appcast.xml --clobber
