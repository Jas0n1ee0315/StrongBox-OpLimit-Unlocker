#!/system/bin/sh
# 開機後（late_start service）套用 patch。
MODDIR=${0%/*}
sh "$MODDIR/apply_patch.sh" "$MODDIR"
