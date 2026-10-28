#!/system/bin/sh
# Bootloop Protector - late boot stage
#   1. waits for the boot to complete, watching zygote for a crash loop
#      and for Volume Up pressed 3 times during the boot animation
#   2. a boot counts as good after 60 more stable seconds
#   3. after TRUST_MINUTES without problems the current setup becomes trusted
#   4. keeps watching for soft reboot loops and (when enabled) SystemUI crashes

MODDIR=${0%/*}
BP_STAGE=service
. "$MODDIR/common.sh"

timeout=$(conf_num BOOT_TIMEOUT 180 60 900)
zmax=$(conf_num ZYGOTE_MAX_RESTARTS 4 2 20)
monitor=$(conf_num SYSTEMUI_MONITOR 1 0 1)
trust_min=$(conf_num TRUST_MINUTES 10 1 120)
volkey=$(conf_num VOLKEY_RESCUE 1 0 1)

shutting_down() { [ -n "$(getprop sys.shutdown.requested)" ]; }

failure() {
  bp_log "FAILURE: $1"
  escalate "$1" && do_reboot
  exit 0
}

# ---------- Volume Up x3 = rescue by hand ----------
# Volume Down x3 is left alone on purpose: KernelSU/SukiSU use it for safe mode.

VK_FLAG="$BP_STATE/volkey"
rm -f "$VK_FLAG"
VK_PID=""
if [ "$volkey" = 1 ] && command -v getevent >/dev/null 2>&1; then
  (
    n=0
    timeout 150 getevent -lq 2>/dev/null | while IFS= read -r line; do
      case "$line" in
        *KEY_VOLUMEUP*DOWN*)
          n=$((n + 1))
          if [ "$n" -ge 3 ]; then
            touch "$VK_FLAG"
            break
          fi
          ;;
      esac
    done
  ) &
  VK_PID=$!
fi

volkey_check() {
  [ -f "$VK_FLAG" ] || return 0
  rm -f "$VK_FLAG"
  bp_log "Volume Up pressed 3 times - rescue asked by hand"
  rescue 1 "volume keys (by hand)"
  state_set level "$RESCUE_LEVEL"
  state_set attempts 0
  refresh_desc
  do_reboot
  exit 0
}

volkey_stop() {
  [ -n "$VK_PID" ] && kill "$VK_PID" 2>/dev/null
  VK_PID=""
  rm -f "$VK_FLAG"
}

zlast=""
zchanges=0
zygote_check() {
  z=$(zygote_pid)
  [ -n "$z" ] || return 0
  if [ -n "$zlast" ] && [ "$z" != "$zlast" ]; then
    zchanges=$((zchanges + 1))
    bp_log "Zygote restarted ($zchanges): $zlast -> $z"
    [ "$zchanges" -ge "$zmax" ] && failure "zygote crash loop ($zchanges restarts)"
  fi
  zlast=$z
}

# ---------- 1. wait for the boot ----------

start=$(now)
while [ "$(getprop sys.boot_completed)" != 1 ]; do
  shutting_down && exit 0
  volkey_check
  zygote_check
  if [ $(( $(now) - start )) -ge "$timeout" ]; then
    bp_log "Boot did not complete in ${timeout}s"
    if [ -f "$BP_STATE/gaveup" ]; then
      bp_log "Gave up earlier - not rebooting"
      exit 0
    fi
    # The next post-fs-data counts this as a failed attempt
    do_reboot
    exit 0
  fi
  sleep 2
done
volkey_stop
bp_log "Boot completed in $(( $(now) - start ))s"

# A rescue in post-fs-data runs before the clock is set - give it the real time now
if [ -f "$BP_STATE/last-rescue" ]; then
  rt=$(grep '^time=' "$BP_STATE/last-rescue" | cut -d= -f2)
  if [ "${rt:-0}" -lt 1000000000 ]; then
    sed -i "s/^time=.*/time=$(now)/" "$BP_STATE/last-rescue"
    refresh_desc
  fi
fi

# ---------- 2. stability window ----------

end=$(( $(now) + 60 ))
while [ "$(now)" -lt "$end" ]; do
  shutting_down && exit 0
  zygote_check
  sleep 3
done

state_set attempts 0
state_set level 0
rm -f "$BP_STATE/gaveup"
take_snapshot "$BP_STATE/candidate"
bp_log "Good boot"
refresh_desc

# ---------- 3 + 4. trust the setup, watch soft reboots and SystemUI ----------

good_at=$(now)
trusted=0
pid_last=$(pidof "$SYSTEMUI")
down_since=0
restarts=""
softs=""

while :; do
  shutting_down && exit 0
  t=$(now)

  if [ "$trusted" = 0 ] && [ $((t - good_at)) -ge $((trust_min * 60)) ]; then
    if [ -s "$BP_STATE/rescue.list" ]; then
      # Modules are switched off by a rescue - this is not the real setup
      rm -f "$BP_STATE/candidate"
      bp_log "Not trusting this setup - a rescue is waiting for Restore"
    else
      mv -f "$BP_STATE/candidate" "$BP_STATE/baseline"
      bp_log "Setup trusted after $trust_min min without problems"
    fi
    trusted=1
    refresh_desc
  fi

  # Soft reboot = zygote restarts without a kernel reboot. One is normal
  # (done by hand or by an app), several in a short time is a loop.
  z=$(zygote_pid)
  if [ -n "$z" ] && [ -n "$zlast" ] && [ "$z" != "$zlast" ]; then
    keep=""
    n=0
    for s in $softs $t; do
      if [ $((t - s)) -lt 300 ]; then keep="$keep $s"; n=$((n + 1)); fi
    done
    softs=$keep
    bp_log "Soft reboot detected ($n in the last 5 min)"
    [ "$n" -ge "$zmax" ] && failure "soft reboot loop ($n zygote restarts in 5 min)"
    # SystemUI comes back on its own after a soft reboot - give it time
    state_set sysui-ignore $((t + 90))
  fi
  [ -n "$z" ] && zlast=$z

  if [ "$monitor" = 1 ]; then
    pid=$(pidof "$SYSTEMUI")
    if [ "$t" -lt "$(state_get sysui-ignore 0)" ]; then
      # Soft reboot or a restart asked from the WebUI
      pid_last=$pid
      down_since=0
      restarts=""
    elif [ -n "$pid" ]; then
      down_since=0
      if [ -n "$pid_last" ] && [ "$pid" != "$pid_last" ]; then
        keep=""
        n=0
        for r in $restarts $t; do
          if [ $((t - r)) -lt 60 ]; then keep="$keep $r"; n=$((n + 1)); fi
        done
        restarts=$keep
        bp_log "SystemUI restarted ($n in the last 60s): $pid_last -> $pid"
        [ "$n" -ge 3 ] && failure "SystemUI crash loop ($n restarts in 60s)"
      fi
      pid_last=$pid
    else
      if [ "$down_since" = 0 ]; then
        down_since=$t
        bp_log "SystemUI is not running"
      elif [ $((t - down_since)) -ge 30 ]; then
        failure "SystemUI not running for $((t - down_since))s"
      fi
    fi
  fi

  if [ "$trusted" = 1 ]; then sleep 10; else sleep 5; fi
done
