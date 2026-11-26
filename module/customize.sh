#!/sbin/sh
# KernelSU / Magisk 安裝流程會呼叫；此時立即套用一次，免得還要重開機。
ui_print "- StrongBox Op-Limit Unlocker"
ui_print "- 目標：TEESimulator-RS / tricky_store v6.0.1-307"
ui_print "- 安裝當下嘗試立即套用..."
set_perm_recursive "$MODPATH" 0 0 0755 0644
sh "$MODPATH/apply_patch.sh" "$MODPATH"
if [ -f "$MODPATH/patch.log" ]; then
  ui_print "- 結果(最後一行)："
  ui_print "    $(tail -n 1 "$MODPATH/patch.log")"
fi
ui_print "- 完成。之後每次開機會自動確保已套用。"
