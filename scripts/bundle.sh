#!/bin/zsh
# Builds MouseDriver.app (release) in ./build and signs it.
#
# macOS ties Accessibility / Input Monitoring grants to the code signature.
# With ad-hoc signing every rebuild looks like a new app and you must re-grant.
# Run scripts/create-signing-cert.sh once to get a stable local identity.
set -euo pipefail
cd "${0:A:h}/.."

IDENTITY_NAME="MouseDriver Local Signing"
APP=build/MouseDriver.app

swift build -c release --product MouseDriver
swift build -c release --product flowctl
BIN=$(swift build -c release --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/MouseDriver" "$APP/Contents/MacOS/MouseDriver"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN/flowctl" build/flowctl

if security find-identity -v -p codesigning | grep -q "Apple Development"; then
  IDENTITY=$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | awk '{print $2}')
elif security find-identity -p codesigning | grep -q "$IDENTITY_NAME"; then
  IDENTITY="$IDENTITY_NAME"
else
  IDENTITY="-"
  echo "note: ad-hoc signing; permissions will need re-granting after each rebuild (see scripts/create-signing-cert.sh)"
fi

codesign --force --options runtime --sign "$IDENTITY" "$APP"
codesign --force --sign "$IDENTITY" build/flowctl
echo "Built $APP (signed with: $IDENTITY)"
echo "Run:  open $APP"
