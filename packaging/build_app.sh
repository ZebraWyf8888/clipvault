#!/bin/bash
# 打包 ClipVault.app（universal 二进制）+ zip + dmg 到 dist/
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' packaging/Info.plist)

# 无完整 Xcode 时 SPM 不支持 --arch 双架构模式，分架构编译后 lipo 合并
echo "==> 构建 release (arm64)"
swift build -c release --triple arm64-apple-macosx14.0
ARM_BIN=$(swift build -c release --triple arm64-apple-macosx14.0 --show-bin-path)/ClipVault

echo "==> 构建 release (x86_64)"
swift build -c release --triple x86_64-apple-macosx14.0
X86_BIN=$(swift build -c release --triple x86_64-apple-macosx14.0 --show-bin-path)/ClipVault

mkdir -p .build/universal
lipo -create "$ARM_BIN" "$X86_BIN" -output .build/universal/ClipVault
BIN_PATH=.build/universal/ClipVault
lipo -info "$BIN_PATH"

APP=dist/ClipVault.app
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp packaging/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp "$BIN_PATH" "$APP/Contents/MacOS/ClipVault"

if [ ! -f packaging/AppIcon.icns ]; then
    bash packaging/make_icns.sh
fi
cp packaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "==> ad-hoc 签名"
codesign --force --deep --sign - "$APP"
codesign --verify --verbose=1 "$APP"

echo "==> 打包 zip + dmg"
ditto -c -k --keepParent "$APP" "dist/ClipVault-$VERSION.zip"

DMG_ROOT=dist/.dmgroot
rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT"
cp -R "$APP" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create -volname ClipVault -srcfolder "$DMG_ROOT" -ov -format UDZO "dist/ClipVault-$VERSION.dmg" >/dev/null
rm -rf "$DMG_ROOT"

echo "==> 完成"
ls -lh dist/
