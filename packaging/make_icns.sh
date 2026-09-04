#!/bin/bash
# 生成 AppIcon.icns（依赖系统自带的 sips / iconutil）
set -euo pipefail
cd "$(dirname "$0")"

swift make_icon.swift icon_1024.png

rm -rf AppIcon.iconset
mkdir -p AppIcon.iconset
for s in 16 32 128 256 512; do
    sips -z "$s" "$s" icon_1024.png --out "AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z "$d" "$d" icon_1024.png --out "AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns AppIcon.iconset -o AppIcon.icns
rm -rf AppIcon.iconset icon_1024.png
echo "packaging/AppIcon.icns 已生成"
