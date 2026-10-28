#!/system/bin/sh
# Bootloop Protector - Action button
# Restores what the last rescue disabled. Without a rescue it shows the status.

MODDIR=${0%/*}
BP_STAGE=action
. "$MODDIR/common.sh"

echo "  Bootloop Protector"
echo "  =================="
echo ""

if [ -s "$BP_STATE/rescue.list" ]; then
  echo "Restoring what the rescue disabled:"
  echo ""
  while IFS= read -r line; do
    echo "  - ${line#*:}"
  done < "$BP_STATE/rescue.list"
  restore
  rm -f "$BP_STATE/gaveup"
  refresh_desc
  echo ""
  echo "Re-enabled $RESTORE_COUNT item(s). Reboot to apply."
  echo "If the problem comes back, the protector will catch it again."
  exit 0
fi

if [ -f "$BP_STATE/gaveup" ]; then
  echo "Status : gave up - the problem is not caused by modules"
else
  echo "Status : armed"
fi
if [ -f "$BP_STATE/baseline" ]; then
  echo "Setup  : trusted"
else
  echo "Setup  : learning (trusted after $(conf_num TRUST_MINUTES 10 1 120) min without problems)"
fi
if [ "$(conf_num SYSTEMUI_MONITOR 1 0 1)" = 1 ]; then
  echo "SystemUI monitor : on"
else
  echo "SystemUI monitor : off"
fi
echo ""
echo "Nothing to restore - no rescue happened."
echo ""
echo "Last log lines:"
tail -n 8 "$BP_LOG" 2>/dev/null | sed 's/^/  /'
