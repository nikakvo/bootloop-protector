#!/system/bin/sh
# Bootloop Protector - early boot stage
# Counts boot attempts. The counter goes back to 0 only after a good boot
# (service.sh), so it keeps growing while the phone fails to boot - also when
# it never reaches service.sh at all.

MODDIR=${0%/*}
BP_STAGE=post-fs-data
. "$MODDIR/common.sh"

attempts=$(( $(state_get attempts 0) + 1 ))
state_set attempts "$attempts"
max=$(conf_num MAX_ATTEMPTS 3 2 10)

if [ "$attempts" -eq 1 ]; then
  bp_log "---------- boot started ----------"
else
  bp_log "---------- boot started (attempt $attempts, previous boot did not finish) ----------"
fi

if [ -f "$BP_STATE/gaveup" ]; then
  bp_log "Gave up earlier - only watching"
  exit 0
fi

if [ "$attempts" -gt "$max" ]; then
  bp_log "Boot loop: $((attempts - 1)) failed boots in a row"
  escalate "boot loop ($((attempts - 1)) failed boots)" && do_reboot
  exit 0
fi

set_desc "⏳ Booting... (attempt $attempts of $max allowed)"
