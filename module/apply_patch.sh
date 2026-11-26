#!/system/bin/sh
# 將 patched classes.dex 套用到 tricky_store，並讓 TEESimulator 重新載入。
# $1 = 本模組目錄（內含 classes.dex.patched）
MODDIR="$1"
TS=/data/adb/modules/tricky_store
DEX="$TS/classes.dex"
PATCHED="$MODDIR/classes.dex.patched"
ORIG_SHA=a90f5e0a333e6e3cadf8231ffe114b858c4c594dc4f9041ea5e55e115f872364
PATCHED_SHA=e23952abe4d894a088d0b434fe4ae25d6c23f6f367c9203a3535912a90bb441b
LOG="$MODDIR/patch.log"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"; }

log "---- apply_patch start ----"

# 1. 等 tricky_store 的 classes.dex 出現（最多 60 秒，給開機時序緩衝）
i=0
while [ ! -f "$DEX" ] && [ "$i" -lt 60 ]; do sleep 1; i=$((i+1)); done
if [ ! -f "$DEX" ]; then log "tricky_store classes.dex 不存在，放棄"; exit 0; fi

cur=$(sha256sum "$DEX" 2>/dev/null | cut -d' ' -f1)
log "目前 tricky_store dex sha=$cur"

# 2. 已經是 patched → 不用做
if [ "$cur" = "$PATCHED_SHA" ]; then log "已是 patched 版，略過"; exit 0; fi

# 3. 不是已知的原始版 → 代表 tricky_store 換版，為避免刷壞，不動手
if [ "$cur" != "$ORIG_SHA" ]; then
  log "警告：tricky_store 非預期版本(hash 不符)，不套用以免損壞。請針對新版重新產生 patch。"
  exit 0
fi

# 4. 確認內附 patched 檔本身完整
ps=$(sha256sum "$PATCHED" 2>/dev/null | cut -d' ' -f1)
if [ "$ps" != "$PATCHED_SHA" ]; then log "錯誤：內附 patched dex 損壞(sha=$ps)，放棄"; exit 0; fi

# 5. 首次先備份原始（以覆蓋內容方式，保留權限/SELinux context）
[ -f "$TS/classes.dex.orig_bak" ] || cp "$DEX" "$TS/classes.dex.orig_bak"
cat "$PATCHED" > "$DEX"
sync
log "已套用 patched dex"

# 6. 讓 TEESimulator 重新載入（supervisor 會自動重拉）
pid=$(pidof TEESimulator 2>/dev/null)
if [ -n "$pid" ]; then
  kill -9 $pid 2>/dev/null
  log "已重啟 TEESimulator (killed $pid)"
fi
log "完成"
exit 0
