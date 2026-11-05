#!/bin/bash
set -euo pipefail
VERSION="${VERSION:-2.0.30}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$ROOT/build}"
APP="$OUT/NetPulse-${VERSION}.app"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
TARGET="arm64-apple-macosx13.0"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" \
         "$APP/Contents/Resources/zh-Hans.lproj" \
         "$APP/Contents/Resources/en.lproj"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>zh_CN</string>
	<key>CFBundleExecutable</key>
	<string>NetPulse</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>com.netpulse.app</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>NetPulse</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>2.0.30</string>
	<key>CFBundleVersion</key>
	<string>230</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.utilities</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>Copyright © 2026 GengLei. All rights reserved.</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSLocationWhenInUseUsageDescription</key>
	<string>NetPulse 需要位置权限以读取当前 Wi‑Fi 名称（SSID）。关闭权限时仍会显示网卡接口名，不影响网速统计。</string>
	<key>NSLocationUsageDescription</key>
	<string>NetPulse 需要位置权限以读取当前 Wi‑Fi 名称（SSID）。关闭权限时仍会显示网卡接口名，不影响网速统计。</string>
</dict>
</plist>
PLIST

echo 'APPL????' > "$APP/Contents/PkgInfo"
cp "$ROOT/NetPulse/Resources/zh-Hans.lproj/Localizable.strings" "$APP/Contents/Resources/zh-Hans.lproj/"
cp "$ROOT/NetPulse/Resources/en.lproj/Localizable.strings" "$APP/Contents/Resources/en.lproj/"

ICONSET="$OUT/AppIcon.iconset"
mkdir -p "$ICONSET"
ICONSRC="$ROOT/NetPulse/Resources/Assets.xcassets/AppIcon.appiconset"
if [ -f "$ICONSRC/icon_128x128@2x.png" ]; then
  BASEIMG="$ICONSRC/icon_128x128@2x.png"
  sips -z 16 16 "$BASEIMG" --out "$ICONSET/icon_16x16.png" >/dev/null
  sips -z 32 32 "$BASEIMG" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$BASEIMG" --out "$ICONSET/icon_32x32.png" >/dev/null
  sips -z 64 64 "$BASEIMG" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$BASEIMG" --out "$ICONSET/icon_128x128.png" >/dev/null
  sips -z 256 256 "$BASEIMG" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$BASEIMG" --out "$ICONSET/icon_256x256.png" >/dev/null
  sips -z 512 512 "$BASEIMG" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$BASEIMG" --out "$ICONSET/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$BASEIMG" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null || true
fi
if [ ! -f "$APP/Contents/Resources/AppIcon.icns" ] && [ -f "/Users/genglei/我的文件/我的编程/网速脉动/源码/Resources/AppIcon.icns" ]; then
  cp "/Users/genglei/我的文件/我的编程/网速脉动/源码/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

echo "[NetPulse] compiling with swiftc..."
# Exclude Tests from app binary
find "$ROOT/NetPulse" -name '*.swift' ! -path '*/Tests/*' -print0 | xargs -0 swiftc -O \
  -target "$TARGET" \
  -sdk "$SDK" \
  -framework AppKit \
  -framework SwiftUI \
  -framework Network \
  -framework UserNotifications \
  -framework ServiceManagement \
  -framework CoreWLAN \
  -framework CoreLocation \
  -framework SystemConfiguration \
  -framework IOKit \
  -o "$APP/Contents/MacOS/NetPulse"

chmod +x "$APP/Contents/MacOS/NetPulse"
xattr -cr "$APP" || true
codesign --force --deep -s - "$APP"
echo "BUILT $APP"
