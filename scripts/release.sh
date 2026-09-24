#!/bin/zsh
# Builds a universal MouseDriver.app and flowctl, then zips them into ./dist
# for a GitHub release.
set -euo pipefail
cd "${0:A:h}/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
UNIVERSAL=1 ./scripts/bundle.sh

rm -rf dist
mkdir -p dist
# ditto keeps the bundle's signature and extended attributes intact; plain zip can break them.
ditto -c -k --keepParent build/MouseDriver.app "dist/MouseDriver-$VERSION.zip"
ditto -c -k build/flowctl "dist/flowctl-$VERSION.zip"
(cd dist && shasum -a 256 *.zip > SHA256SUMS.txt)
ls -l dist
