#!/usr/bin/env bash
# Builds SimMan.app into build/. Pass --install to copy it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
app=build/SimMan.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/SimMan" "$app/Contents/MacOS/SimMan"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.johansorensen.simman</string>
  <key>CFBundleName</key><string>SimMan</string>
  <key>CFBundleExecutable</key><string>SimMan</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$app"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p ~/Applications
  rm -rf ~/Applications/SimMan.app
  cp -R "$app" ~/Applications/
  echo "Installed ~/Applications/SimMan.app"
fi
