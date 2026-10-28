#!/system/bin/sh
# Bootloop Protector - command line used by the WebUI and the Action button
# Usage: su -c 'sh /data/adb/modules/bootloop-protector/bp.sh <command>'

MODDIR=${0%/*}
BP_STAGE=cli
. "$MODDIR/common.sh"

T="$(printf '\t')"

valid_id() {
  case "$1" in ''|*[!A-Za-z0-9._-]*) return 1 ;; esac
  return 0
}

# list_set FILE ENTRY 0|1 - add or remove one exact line, comments stay
list_set() {
  touch "$1"
  if [ "$3" = 1 ]; then
    grep -Fxq "$2" "$1" || echo "$2" >> "$1"
  else
    grep -Fxv "$2" "$1" > "$1.tmp"
    cat "$1.tmp" > "$1"
    rm -f "$1.tmp"
  fi
}

in_rescue() {
  grep -Fxq "$1" "$BP_STATE/rescue.list" 2>/dev/null
}

case "$1" in
  status)
    echo "now=$(now)"
    echo "uptime=$(cut -d. -f1 /proc/uptime)"
    echo "version=$(prop_get "$MODDIR" version)"
    echo "attempts=$(state_get attempts 0)"
    echo "max_attempts=$(conf_num MAX_ATTEMPTS 3 2 10)"
    echo "level=$(state_get level 0)"
    [ -f "$BP_STATE/gaveup" ] && echo "gaveup=1" || echo "gaveup=0"
    [ -f "$BP_STATE/baseline" ] && echo "trusted=1" || echo "trusted=0"
    echo "trusted_time=$(stat -c %Y "$BP_STATE/baseline" 2>/dev/null)"
    echo "trust_minutes=$(conf_num TRUST_MINUTES 10 1 120)"
    echo "boot_completed=$(getprop sys.boot_completed)"
    echo "systemui_monitor=$(conf_num SYSTEMUI_MONITOR 1 0 1)"
    echo "volkey=$(conf_num VOLKEY_RESCUE 1 0 1)"
    echo "systemui_pid=$(pidof "$SYSTEMUI")"
    echo "zygote_pid=$(zygote_pid)"
    if [ -f "$BP_STATE/last-rescue" ]; then
      sed 's/^/rescue_/' "$BP_STATE/last-rescue"
    fi
    if [ -s "$BP_STATE/rescue.list" ]; then
      echo "rescue_items=$(grep -c . "$BP_STATE/rescue.list")"
    else
      echo "rescue_items=0"
    fi
    echo "log_size=$(cat "$BP_LOG" "$BP_LOG.old" 2>/dev/null | wc -c)"
    ;;

  modules)
    # id <tab> name <tab> version <tab> state <tab> never-disable
    for m in "$MODULES_DIR"/*/; do
      m="${m%/}"
      [ -d "$m" ] || continue
      id="${m##*/}"
      name=$(prop_get "$m" name | tr '\t' ' ')
      ver=$(prop_get "$m" version | tr '\t' ' ')
      allow=0
      if [ "$id" = "$BP_ID" ]; then
        state=self
      else
        list_clean "$BP_DATA/allowed-modules.txt" | grep -Fxq "$id" && allow=1
        if [ -f "$m/remove" ]; then
          state=removing
        elif [ -f "$m/disable" ]; then
          if in_rescue "module:$id"; then state=rescued; else state=disabled; fi
        elif [ -d "$ADB/modules_update/$id" ] || [ -f "$m/update" ]; then
          state=pending
        elif [ ! -f "$BP_STATE/baseline" ]; then
          state=learning
        elif grep -Fxq "module:$id $(mod_fp "$m")" "$BP_STATE/baseline"; then
          state=trusted
        elif grep -q "^module:$id " "$BP_STATE/baseline"; then
          state=changed
        else
          state=new
        fi
      fi
      echo "$id$T${name:-$id}$T$ver$T$state$T$allow"
    done
    ;;

  scripts)
    # folder <tab> name <tab> path <tab> state <tab> never-disable
    for d in $SCRIPT_DIRS; do
      [ -d "$d" ] || continue
      for s in "$d"/* "$d"/.[!.]*; do
        [ -f "$s" ] || continue
        n="${s##*/}"
        allow=0
        list_clean "$BP_DATA/allowed-scripts.txt" | grep -Fxq "$n" && allow=1
        if [ ! -x "$s" ]; then
          if in_rescue "script:$s"; then state=rescued; else state=off; fi
        elif [ ! -f "$BP_STATE/baseline" ]; then
          state=learning
        elif grep -Fxq "script:$s $(cksum < "$s" | cut -d' ' -f1)" "$BP_STATE/baseline"; then
          state=trusted
        elif grep -Fq "script:$s " "$BP_STATE/baseline"; then
          state=changed
        else
          state=new
        fi
        echo "${d##*/}$T$n$T$s$T$state$T$allow"
      done
    done
    ;;

  allow-module)
    valid_id "$2" || { echo "Bad module id"; exit 1; }
    [ "$2" = "$BP_ID" ] && exit 0
    list_set "$BP_DATA/allowed-modules.txt" "$2" "$3"
    bp_log "Never disable $2: $([ "$3" = 1 ] && echo on || echo off)"
    echo "ok"
    ;;

  allow-script)
    case "$2" in ''|*/*) echo "Bad script name"; exit 1 ;; esac
    list_set "$BP_DATA/allowed-scripts.txt" "$2" "$3"
    bp_log "Never disable script $2: $([ "$3" = 1 ] && echo on || echo off)"
    echo "ok"
    ;;

  conf)
    echo "MAX_ATTEMPTS=$(conf_num MAX_ATTEMPTS 3 2 10)"
    echo "BOOT_TIMEOUT=$(conf_num BOOT_TIMEOUT 180 60 900)"
    echo "ZYGOTE_MAX_RESTARTS=$(conf_num ZYGOTE_MAX_RESTARTS 4 2 20)"
    echo "SYSTEMUI_MONITOR=$(conf_num SYSTEMUI_MONITOR 1 0 1)"
    echo "TRUST_MINUTES=$(conf_num TRUST_MINUTES 10 1 120)"
    echo "VOLKEY_RESCUE=$(conf_num VOLKEY_RESCUE 1 0 1)"
    ;;

  set-conf)
    case "$2" in
      MAX_ATTEMPTS) lo=2; hi=10 ;;
      BOOT_TIMEOUT) lo=60; hi=900 ;;
      ZYGOTE_MAX_RESTARTS) lo=2; hi=20 ;;
      SYSTEMUI_MONITOR|VOLKEY_RESCUE) lo=0; hi=1 ;;
      TRUST_MINUTES) lo=1; hi=120 ;;
      *) echo "Unknown setting"; exit 1 ;;
    esac
    case "$3" in ''|*[!0-9]*) echo "Bad value"; exit 1 ;; esac
    if [ "$3" -lt "$lo" ] || [ "$3" -gt "$hi" ]; then echo "Out of range"; exit 1; fi
    conf_set "$2" "$3"
    bp_log "Setting $2=$3"
    refresh_desc
    echo "ok"
    ;;

  rescue-list)
    cat "$BP_STATE/rescue.list" 2>/dev/null
    ;;

  restore)
    restore
    refresh_desc
    echo "Re-enabled $RESTORE_COUNT item(s). Reboot to apply."
    ;;

  dismiss)
    # Keep the rescued items disabled, just close the rescue
    rm -f "$BP_STATE/rescue.list" "$BP_STATE/last-rescue" "$BP_STATE/gaveup"
    bp_log "Rescue closed - disabled items stay disabled"
    refresh_desc
    echo "Rescue closed. The items stay disabled."
    ;;

  disable-all)
    rescue 2 "by hand (disable all)"
    refresh_desc
    echo "Disabled $RESCUE_COUNT item(s). Reboot to apply."
    ;;

  enable-all)
    n=0
    for m in "$MODULES_DIR"/*/; do
      m="${m%/}"
      if [ -f "$m/disable" ]; then rm -f "$m/disable"; n=$((n + 1)); fi
    done
    restore >/dev/null
    bp_log "Enabled all modules ($n)"
    refresh_desc
    echo "Enabled $n module(s). Reboot to apply."
    ;;

  trust-now)
    take_snapshot "$BP_STATE/baseline"
    rm -f "$BP_STATE/candidate"
    bp_log "Current setup marked as trusted by hand"
    refresh_desc
    echo "Current setup is now trusted."
    ;;

  restart-systemui)
    state_set sysui-ignore $(( $(now) + 30 ))
    bp_log "SystemUI restart asked by hand"
    kill $(pidof "$SYSTEMUI") 2>/dev/null
    echo "SystemUI restarted."
    ;;

  log)
    cat "$BP_LOG.old" "$BP_LOG" 2>/dev/null
    ;;

  clear-log)
    rm -f "$BP_LOG" "$BP_LOG.old"
    bp_log "Log cleared"
    echo "Log cleared."
    ;;

  *)
    echo "Commands: status, modules, scripts, conf, set-conf KEY VALUE,"
    echo "          allow-module ID 0|1, allow-script NAME 0|1, rescue-list,"
    echo "          restore, dismiss, disable-all, enable-all, trust-now,"
    echo "          restart-systemui, log, clear-log"
    exit 1
    ;;
esac
