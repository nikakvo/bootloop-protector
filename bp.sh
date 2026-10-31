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

# load_lists - allow lists, rescue list and trusted setup in variables,
# one entry per line with a newline on both ends for exact matching
load_lists() {
  ALLOWED_M="$NL$(list_clean "$BP_DATA/allowed-modules.txt")$NL"
  ALLOWED_S="$NL$(list_clean "$BP_DATA/allowed-scripts.txt")$NL"
  RESCUED="$NL$(cat "$BP_STATE/rescue.list" 2>/dev/null)$NL"
  if [ -f "$BP_STATE/baseline" ]; then
    HAVE_BASE=1
    BASE="$NL$(cat "$BP_STATE/baseline")$NL"
  else
    HAVE_BASE=0
    BASE=""
  fi
}

cmd_modules() {
  # id <tab> name <tab> version <tab> state <tab> never-disable
  # Lists are read once here, not once per module - this is what the WebUI waits for
  load_lists
  for m in "$MODULES_DIR"/*/; do
    m="${m%/}"
    [ -d "$m" ] || continue
    id="${m##*/}"
    read_props "$m"
    name=${P_NAME//$T/ }
    ver=${P_VERSION//$T/ }
    allow=0
    if [ "$id" = "$BP_ID" ]; then
      state=self
    else
      case "$ALLOWED_M" in *"$NL$id$NL"*) allow=1 ;; esac
      if [ -f "$m/remove" ]; then
        state=removing
      elif [ -f "$m/disable" ]; then
        case "$RESCUED" in *"${NL}module:$id$NL"*) state=rescued ;; *) state=disabled ;; esac
      elif [ -d "$ADB/modules_update/$id" ] || [ -f "$m/update" ]; then
        state=pending
      elif [ "$HAVE_BASE" = 0 ]; then
        state=learning
      else
        fp=$(mod_fp "$m")
        case "$BASE" in
          *"${NL}module:$id $fp$NL"*) state=trusted ;;
          *"${NL}module:$id "*) state=changed ;;
          *) state=new ;;
        esac
      fi
    fi
    echo "$id$T${name:-$id}$T$ver$T$state$T$allow"
  done
}

cmd_scripts() {
  # folder <tab> name <tab> path <tab> state <tab> never-disable
  load_lists
  for d in $SCRIPT_DIRS; do
    [ -d "$d" ] || continue
    for s in "$d"/* "$d"/.[!.]*; do
      [ -f "$s" ] || continue
      n="${s##*/}"
      allow=0
      case "$ALLOWED_S" in *"$NL$n$NL"*) allow=1 ;; esac
      if [ ! -x "$s" ]; then
        case "$RESCUED" in *"${NL}script:$s$NL"*) state=rescued ;; *) state=off ;; esac
      elif [ "$HAVE_BASE" = 0 ]; then
        state=learning
      else
        ck=$(cksum < "$s")
        ck=${ck%% *}
        case "$BASE" in
          *"${NL}script:$s $ck$NL"*) state=trusted ;;
          *"${NL}script:$s "*) state=changed ;;
          *) state=new ;;
        esac
      fi
      echo "${d##*/}$T$n$T$s$T$state$T$allow"
    done
  done
}

cmd_conf() {
  echo "MAX_ATTEMPTS=$(conf_num MAX_ATTEMPTS 3 2 10)"
  echo "BOOT_TIMEOUT=$(conf_num BOOT_TIMEOUT 180 60 900)"
  echo "ZYGOTE_MAX_RESTARTS=$(conf_num ZYGOTE_MAX_RESTARTS 4 2 20)"
  echo "SYSTEMUI_MONITOR=$(conf_num SYSTEMUI_MONITOR 1 0 1)"
  echo "TRUST_MINUTES=$(conf_num TRUST_MINUTES 10 1 120)"
  echo "VOLKEY_RESCUE=$(conf_num VOLKEY_RESCUE 1 0 1)"
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
    cmd_modules
    ;;

  scripts)
    cmd_scripts
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
    cmd_conf
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

  save-log)
    # Log plus a short report (version, device, settings, rescue, modules) for bug reports
    dir=""
    for d in /sdcard/Download /storage/emulated/0/Download; do
      [ -d "$d" ] && { dir=$d; break; }
    done
    [ -n "$dir" ] || { echo "Download folder not found"; exit 1; }
    f="$dir/bootloop-protector-$(date '+%Y%m%d-%H%M%S').log"
    root=""
    [ -d "$ADB/ksu" ] && root="$root KernelSU/SukiSU"
    [ -d "$ADB/ap" ] && root="$root APatch"
    [ -d "$ADB/magisk" ] && root="$root Magisk"
    umask 022
    {
      echo "Bootloop Protector $(prop_get "$MODDIR" version) - saved $(date '+%Y-%m-%d %H:%M:%S')"
      echo "Device : $(getprop ro.product.manufacturer) $(getprop ro.product.model)"
      echo "Android: $(getprop ro.build.version.release) (SDK $(getprop ro.build.version.sdk))"
      echo "Kernel : $(uname -r)"
      echo "Root   :${root:- unknown}"
      echo ""
      echo "== settings =="
      cmd_conf
      echo ""
      echo "== state =="
      echo "attempts=$(state_get attempts 0) level=$(state_get level 0)" \
        "trusted=$([ -f "$BP_STATE/baseline" ] && echo yes || echo no)" \
        "gaveup=$([ -f "$BP_STATE/gaveup" ] && echo yes || echo no)"
      if [ -f "$BP_STATE/last-rescue" ]; then
        echo "last rescue: $(tr '\n' ' ' < "$BP_STATE/last-rescue")"
      fi
      if [ -s "$BP_STATE/rescue.list" ]; then
        echo "waiting for Restore:"
        sed 's/^/  /' "$BP_STATE/rescue.list"
      fi
      echo ""
      echo "== modules (id, version, state, never disable) =="
      # empty fields become "-" so read does not merge the tabs
      cmd_modules | sed -e "s/$T$T/$T-$T/g" -e "s/$T$T/$T-$T/g" | while IFS="$T" read -r id name ver st al; do
        echo "  $id  $ver  $st$([ "$al" = 1 ] && echo '  never-disable')"
      done
      echo ""
      echo "== scripts (folder, name, state) =="
      cmd_scripts | sed -e "s/$T$T/$T-$T/g" -e "s/$T$T/$T-$T/g" | while IFS="$T" read -r fo n p st al; do
        echo "  $fo/$n  $st$([ "$al" = 1 ] && echo '  never-disable')"
      done
      echo ""
      echo "== log =="
      cat "$BP_LOG.old" "$BP_LOG" 2>/dev/null
    } > "$f" 2>/dev/null
    [ -s "$f" ] || { rm -f "$f" 2>/dev/null; echo "Could not write to $dir"; exit 1; }
    chmod 644 "$f" 2>/dev/null
    echo "Saved to Download/${f##*/}"
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
    echo "          restart-systemui, log, save-log, clear-log"
    exit 1
    ;;
esac
