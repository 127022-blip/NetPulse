#!/bin/bash
set -euo pipefail
# 版本单一来源：优先环境变量，其次 VERSION 文件，再次 Constants.swift
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# 兼容根目录 build.sh 与 NetPulse-main/build.sh
if [ -d "$SCRIPT_DIR/NetPulse-main/NetPulse" ]; then
  ROOT="$SCRIPT_DIR/NetPulse-main"
  DELIVER_DIR="$SCRIPT_DIR"
elif [ -d "$SCRIPT_DIR/NetPulse" ]; then
  ROOT="$SCRIPT_DIR"
  DELIVER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
else
  echo "找不到 NetPulse 源码目录" >&2
  exit 1
fi

if [ -n "${VERSION:-}" ]; then
  :
elif [ -f "$ROOT/VERSION" ]; then
  VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
else
  VERSION="$(grep -E 'static let version' "$ROOT/NetPulse/Utilities/Constants.swift" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
fi
BUILD_NUM="$(grep -E 'static let build' "$ROOT/NetPulse/Utilities/Constants.swift" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
BUILD_NUM="${BUILD_NUM:-240}"

OUT="${1:-$DELIVER_DIR/build}"
APP="$OUT/NetPulse-${VERSION}.app"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
TARGET="arm64-apple-macosx13.0"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" \
         "$APP/Contents/Resources/zh-Hans.lproj" \
         "$APP/Contents/Resources/en.lproj"

# Info.plist 从 Constants 注入版本与版权（无句号）
cat > "$APP/Contents/Info.plist" <<PLIST
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
	<string>${VERSION}</string>
	<key>CFBundleVersion</key>
	<string>${BUILD_NUM}</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.utilities</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>Copyright © 2026 Geng Lei</string>
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
# 图标只从仓库资源；无外部绝对路径回退

echo "[NetPulse] compiling ${VERSION} (${BUILD_NUM}) with clang + swiftc..."
SMC_OBJ="$OUT/SMCBridge.o"
clang -c "$ROOT/NetPulse/Services/SMCBridge.c" -o "$SMC_OBJ" \
  -isysroot "$SDK" -mmacosx-version-min=13.0 -arch arm64 \
  -I "$ROOT/NetPulse/Services" -std=c11

SWIFT_FILES=()
while IFS= read -r -d '' f; do
  SWIFT_FILES+=("$f")
done < <(find "$ROOT/NetPulse" -name '*.swift' ! -path '*/Tests/*' ! -path '*/WIP/*' -print0)

swiftc -O \
  -target "$TARGET" \
  -sdk "$SDK" \
  -import-objc-header "$ROOT/NetPulse/Services/NetPulse-Bridging-Header.h" \
  -I "$ROOT/NetPulse/Services" \
  -framework AppKit \
  -framework SwiftUI \
  -framework Network \
  -framework UserNotifications \
  -framework ServiceManagement \
  -framework CoreWLAN \
  -framework CoreLocation \
  -framework SystemConfiguration \
  -framework IOKit \
  "$SMC_OBJ" \
  "${SWIFT_FILES[@]}" \
  -o "$APP/Contents/MacOS/NetPulse"

chmod +x "$APP/Contents/MacOS/NetPulse"
xattr -cr "$APP" || true
codesign --force --deep -s - "$APP"
# 交付到文件夹根目录（先删再拷，避免落入已存在的 .app 目录造成嵌套）
rm -rf "$DELIVER_DIR/NetPulse-${VERSION}.app"
cp -R "$APP" "$DELIVER_DIR/NetPulse-${VERSION}.app"
echo "BUILT $APP"
echo "DELIVERED $DELIVER_DIR/NetPulse-${VERSION}.app"
