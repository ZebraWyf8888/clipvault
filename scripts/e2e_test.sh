#!/bin/bash
# 端到端测试：真实启动 ClipVault，真实写系统剪贴板，验证捕获规则与加密落盘。
# 注意：运行期间会短暂占用系统剪贴板，结束时恢复原有文本内容。
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> 构建"
swift build 2>&1 | tail -1

BIN=.build/debug/ClipVault
DUMP=.build/debug/cvdump
DATA_DIR=$(mktemp -d "${TMPDIR:-/tmp}/clipvault-e2e.XXXXXX")

# 测试专用设置：图片上限压到 50 KB，便于用小图触发「过大」拒绝
SETTINGS='{"retentionHours":72,"maxItems":500,"keepImages":true,"maxImageBytes":51200,"maxTextBytes":1048576,"skipConcealed":true,"skipTransient":true,"secretPolicy":"mask","excludedBundleIDs":[],"persistToDisk":true,"autoPaste":false,"launchAtLogin":false,"hotkey":"ctrlShiftV"}'

OLD_CLIP=$(pbpaste 2>/dev/null || true)

echo "==> 启动 ClipVault（数据目录: $DATA_DIR）"
CLIPVAULT_DATA_DIR="$DATA_DIR" CLIPVAULT_POLL_MS=80 CLIPVAULT_SETTINGS_JSON="$SETTINGS" "$BIN" &
APP_PID=$!
trap 'kill $APP_PID 2>/dev/null || true; rm -rf "$DATA_DIR"' EXIT
sleep 2

if ! kill -0 "$APP_PID" 2>/dev/null; then
    echo "FAIL: ClipVault 启动即退出"
    exit 1
fi

echo "==> 写入各类剪贴板内容"
printf 'hello clipvault e2e' | pbcopy; sleep 0.6

# 2 MB 文本，超过 1 MB 上限 → 应被拒绝
head -c 2000000 /dev/zero | tr '\0' 'a' | pbcopy; sleep 0.8

# 假 token（格式命中检测规则，非真实凭证）→ 应被记录但遮罩
FAKE_TOKEN="ghp_Fake0Fake0Fake0Fake0Fake0Fake0Fake0"
printf '%s' "$FAKE_TOKEN" | pbcopy; sleep 0.6

# Concealed 标记（模拟密码管理器）→ 应被跳过
swift scripts/set_pasteboard.swift concealed "concealed-e2e-should-not-appear"; sleep 0.6

# 小图（约 6 KB < 50 KB）→ 应被保留
swift scripts/set_pasteboard.swift image 40 40 >/dev/null; sleep 0.8

# 大图（噪点 200x200 约 160 KB > 50 KB）→ 应被拒绝
swift scripts/set_pasteboard.swift image 200 200 >/dev/null; sleep 0.8

printf 'final marker text' | pbcopy
sleep 1.5   # 等 debounce 落盘

echo "==> 停止应用并读取加密存储"
kill "$APP_PID"; wait "$APP_PID" 2>/dev/null || true
sleep 0.3

OUT=$("$DUMP" "$DATA_DIR")
echo "$OUT"

FAIL=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAIL=1; }

echo "$OUT" | grep -qF 'hello clipvault e2e' && pass '普通文本被记录' || fail '普通文本被记录'
echo "$OUT" | grep -qF 'final marker text' && pass '结尾文本被记录' || fail '结尾文本被记录'
echo "$OUT" | grep -qF 'aaaaaaaaaaaaaaaa' && fail '超大文本被拒绝' || pass '超大文本被拒绝'
echo "$OUT" | grep -qF "$FAKE_TOKEN" && fail 'token 明文不出现在列表（遮罩）' || pass 'token 明文不出现在列表（遮罩）'
echo "$OUT" | grep -Eq '"sensitive"[[:space:]]*:[[:space:]]*true' && pass 'token 条目被标记为敏感' || fail 'token 条目被标记为敏感'
echo "$OUT" | grep -qF 'concealed-e2e-should-not-appear' && fail 'Concealed 内容被跳过' || pass 'Concealed 内容被跳过'

IMG_COUNT=$(echo "$OUT" | grep -Ec '"kind"[[:space:]]*:[[:space:]]*"image"' || true)
if [ "$IMG_COUNT" = "1" ]; then
    pass "小图保留、大图拒绝（image 条目数 = 1）"
else
    fail "小图保留、大图拒绝（image 条目数 = $IMG_COUNT，期望 1）"
fi

# 加密验证：数据目录里任何文件都不应包含明文
if grep -Rqa 'hello clipvault e2e' "$DATA_DIR" 2>/dev/null; then
    fail '磁盘无明文（加密落盘）'
else
    pass '磁盘无明文（加密落盘）'
fi
if grep -Rqa "$FAKE_TOKEN" "$DATA_DIR" 2>/dev/null; then
    fail 'token 在磁盘上无明文'
else
    pass 'token 在磁盘上无明文'
fi

echo "==> 恢复原剪贴板"
printf '%s' "$OLD_CLIP" | pbcopy || true

if [ "$FAIL" = "0" ]; then
    echo "==> e2e 全部通过 ✅"
else
    echo "==> e2e 存在失败 ❌"
fi
exit "$FAIL"
