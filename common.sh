#!/system/bin/sh
# Bootloop Protector - shared functions
# Sourced by post-fs-data.sh, service.sh, action.sh and bp.sh.
# BP_ROOT is empty on the device; it only exists to test the logic off-device.

BP_ID="bootloop-protector"
ADB="${BP_ROOT:-}/data/adb"
MODULES_DIR="$ADB/modules"
BP_MOD="$MODULES_DIR/$BP_ID"
BP_DATA="$ADB/bootloop-protector"
BP_STATE="$BP_DATA/state"
BP_CONF="$BP_DATA/config"
BP_LOG="$BP_DATA/bp.log"
BP_LOG_MAX=524288
SCRIPT_DIRS="$ADB/post-fs-data.d $ADB/post-mount.d $ADB/service.d $ADB/boot-completed.d"
SYSTEMUI="com.android.systemui"

umask 077
mkdir -p "$BP_STATE" 2>/dev/null

# The real zygote is the zygote64/zygote process started by init (parent 1).
# Freshly forked children briefly carry the same name, so pidof alone is not enough.
zygote_pid() {
  for p in $(pidof zygote64 2>/dev/null) $(pidof zygote 2>/dev/null); do
    pp=$(cut -d' ' -f4 "/proc/$p/stat" 2>/dev/null)
    if [ "$pp" = 1 ]; then echo "$p"; return; fi
  done
}

# ---------- logging ----------

bp_log() {
  if [ -f "$BP_LOG" ]; then
    size=$(wc -c < "$BP_LOG" 2>/dev/null)
    [ "${size:-0}" -gt "$BP_LOG_MAX" ] && mv -f "$BP_LOG" "$BP_LOG.old"
  fi
  stamp=$(date '+%Y-%m-%d %H:%M:%S')
  case "$stamp" in 19*) stamp="(clock not set)    " ;; esac
  echo "$stamp [${BP_STAGE:-cli}] $*" >> "$BP_LOG"
}

# ---------- config and state ----------

# conf_num KEY DEFAULT MIN MAX - numeric setting, falls back to DEFAULT when invalid
conf_num() {
  v=$(grep -m1 "^$1=" "$BP_CONF" 2>/dev/null | cut -d= -f2- | tr -d '\r\t ')
  case "$v" in ''|*[!0-9]*) echo "$2"; return ;; esac
  if [ "$v" -lt "$3" ] || [ "$v" -gt "$4" ]; then echo "$2"; else echo "$v"; fi
}

# conf_set KEY VALUE - change or add one setting, keeping comments
conf_set() {
  if grep -q "^$1=" "$BP_CONF" 2>/dev/null; then
    sed -i "s/^$1=.*/$1=$2/" "$BP_CONF"
  else
    echo "$1=$2" >> "$BP_CONF"
  fi
}

state_get() {
  v=$(cat "$BP_STATE/$1" 2>/dev/null)
  echo "${v:-$2}"
}

state_set() {
  echo "$2" > "$BP_STATE/$1"
}

now() { date +%s; }

# list_clean FILE - list entries without comments, blank lines or CR
list_clean() {
  [ -f "$1" ] || return 0
  sed -e 's/\r$//' -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$1" | grep -v '^$'
}

module_allowed() {
  [ "$1" = "$BP_ID" ] && return 0
  list_clean "$BP_DATA/allowed-modules.txt" | grep -Fxq "$1"
}

script_allowed() {
  list_clean "$BP_DATA/allowed-scripts.txt" | grep -Fxq "${1##*/}"
}

# ---------- snapshots ----------

prop_get() {
  grep -m1 "^$2=" "$1/module.prop" 2>/dev/null | cut -d= -f2- | tr -d '\r'
}

CR=$(printf '\r')
NL='
'

# read_props DIR - sets P_NAME, P_VERSION and P_VCODE from DIR/module.prop.
# Same result as prop_get (first match, CR removed) but with no extra processes,
# which matters when the WebUI lists many modules.
read_props() {
  P_NAME=""; P_VERSION=""; P_VCODE=""
  _pn=0; _pv=0; _pc=0
  [ -f "$1/module.prop" ] || return 0
  while IFS= read -r _l || [ -n "$_l" ]; do
    case "$_l" in
      name=*) [ "$_pn" = 0 ] && { P_NAME=${_l#name=}; _pn=1; } ;;
      version=*) [ "$_pv" = 0 ] && { P_VERSION=${_l#version=}; _pv=1; } ;;
      versionCode=*) [ "$_pc" = 0 ] && { P_VCODE=${_l#versionCode=}; _pc=1; } ;;
    esac
  done < "$1/module.prop"
  P_NAME=${P_NAME//$CR/}
  P_VERSION=${P_VERSION//$CR/}
  P_VCODE=${P_VCODE//$CR/}
}

# Fingerprint of everything in a module that can break a boot.
# The description line is left out on purpose: many modules rewrite it on every boot.
# The output is the same as in v1.0 (trusted setups stay valid), it only uses
# far fewer processes: one cksum for all boot files and no grep/cut per prop.
mod_fp() {
  (
    cd "$1" 2>/dev/null || exit 0
    read_props .
    echo "$P_VCODE|$P_VERSION"
    set --
    for f in post-fs-data.sh post-mount.sh service.sh boot-completed.sh system.prop sepolicy.rule; do
      [ -f "$f" ] && set -- "$@" "$f"
    done
    [ $# -gt 0 ] && cksum "$@"
    find system vendor product system_ext odm zygisk -type f 2>/dev/null | wc -l
    du -sk system vendor product system_ext odm zygisk 2>/dev/null
  ) | cksum | { read -r _c _r; echo "$_c"; }
}

# Every executable general script (hidden ones too)
list_scripts() {
  for d in $SCRIPT_DIRS; do
    [ -d "$d" ] || continue
    for s in "$d"/* "$d"/.[!.]*; do
      [ -f "$s" ] && [ -x "$s" ] && echo "$s"
    done
  done
}

# take_snapshot FILE - enabled modules and executable scripts with fingerprints
take_snapshot() {
  tmp="$1.tmp"
  : > "$tmp"
  for m in "$MODULES_DIR"/*/; do
    m="${m%/}"
    [ -d "$m" ] || continue
    id="${m##*/}"
    [ "$id" = "$BP_ID" ] && continue
    [ -f "$m/disable" ] || [ -f "$m/remove" ] && continue
    echo "module:$id $(mod_fp "$m")" >> "$tmp"
  done
  list_scripts | while IFS= read -r s; do
    echo "script:$s $(cksum < "$s" | cut -d' ' -f1)" >> "$tmp"
  done
  mv -f "$tmp" "$1"
}

# ---------- rescue ----------

disable_module() {
  m="$MODULES_DIR/$1"
  [ -d "$m" ] || return 1
  if module_allowed "$1"; then bp_log "  keep module $1 (allowed)"; return 1; fi
  [ -f "$m/disable" ] && return 1
  # Record first, then disable: if the rescue is cut off in between, Restore
  # still knows about it (Restore skips items that are not really disabled)
  echo "module:$1" >> "$BP_STATE/rescue.list"
  touch "$m/disable"
  bp_log "  disabled module $1"
}

disable_script() {
  [ -f "$1" ] && [ -x "$1" ] || return 1
  if script_allowed "$1"; then bp_log "  keep script $1 (allowed)"; return 1; fi
  echo "script:$1" >> "$BP_STATE/rescue.list"
  chmod 644 "$1"
  bp_log "  disabled script $1"
}

# rescue LEVEL REASON
#   level 1 - only modules and scripts that are new or changed since the trusted setup
#   level 2 - every module and script (except allowed ones and this module)
rescue() {
  level=$1
  reason=$2
  count=0
  if [ "$level" = 1 ]; then
    if [ ! -f "$BP_STATE/baseline" ]; then
      bp_log "No trusted setup recorded yet - going straight to level 2"
      level=2
    else
      take_snapshot "$BP_STATE/now"
      grep -Fxv -f "$BP_STATE/baseline" "$BP_STATE/now" > "$BP_STATE/suspects"
      rm -f "$BP_STATE/now"
      if [ ! -s "$BP_STATE/suspects" ]; then
        bp_log "Nothing changed since the trusted setup - going to level 2"
        level=2
      fi
    fi
  fi

  bp_log "RESCUE level $level - reason: $reason"
  if [ "$level" = 1 ]; then
    while IFS= read -r line; do
      key="${line% *}"
      case "$key" in
        module:*) disable_module "${key#module:}" && count=$((count + 1)) ;;
        script:*) disable_script "${key#script:}" && count=$((count + 1)) ;;
      esac
    done < "$BP_STATE/suspects"
  else
    for m in "$MODULES_DIR"/*/; do
      m="${m%/}"
      [ -d "$m" ] || continue
      disable_module "${m##*/}" && count=$((count + 1))
    done
    list_scripts > "$BP_STATE/scripts.tmp"
    while IFS= read -r s; do
      disable_script "$s" && count=$((count + 1))
    done < "$BP_STATE/scripts.tmp"
    rm -f "$BP_STATE/scripts.tmp"
  fi
  rm -f "$BP_STATE/suspects"
  # A rescue that found nothing new to switch off keeps the record of the one before
  if [ "$count" -gt 0 ] || [ ! -f "$BP_STATE/last-rescue" ]; then
    printf 'time=%s\nlevel=%s\nreason=%s\ncount=%s\n' "$(now)" "$level" "$reason" "$count" > "$BP_STATE/last-rescue"
  fi
  bp_log "RESCUE done - $count item(s) disabled"
  RESCUE_LEVEL=$level
  RESCUE_COUNT=$count
}

# restore - undo exactly what the rescues disabled, nothing else
restore() {
  n=0
  if [ -f "$BP_STATE/rescue.list" ]; then
    while IFS= read -r line; do
      case "$line" in
        module:*)
          id="${line#module:}"
          if [ -f "$MODULES_DIR/$id/disable" ]; then
            rm -f "$MODULES_DIR/$id/disable"
            bp_log "  restored module $id"
            n=$((n + 1))
          fi
          ;;
        script:*)
          s="${line#script:}"
          if [ -f "$s" ]; then
            chmod 755 "$s"
            bp_log "  restored script $s"
            n=$((n + 1))
          fi
          ;;
      esac
    done < "$BP_STATE/rescue.list"
  fi
  rm -f "$BP_STATE/rescue.list" "$BP_STATE/last-rescue" "$BP_STATE/gaveup"
  # A restore is only possible from a booted phone, so start counting fresh
  state_set attempts 0
  state_set level 0
  bp_log "Restore done - $n item(s) re-enabled"
  RESTORE_COUNT=$n
}

# escalate REASON - run the next rescue level, or give up when both were used.
# Returns 0 when a rescue ran (caller should reboot), 1 when it gave up.
escalate() {
  cur=$(state_get level 0)
  next=$((cur + 1))
  if [ "$next" -gt 2 ]; then
    if [ ! -f "$BP_STATE/gaveup" ]; then
      touch "$BP_STATE/gaveup"
      bp_log "Both rescue levels were used and the problem is still there ($1)."
      bp_log "It is not caused by modules or scripts - no more reboots until a good boot."
    fi
    refresh_desc
    return 1
  fi
  rescue "$next" "$1"
  state_set level "$RESCUE_LEVEL"
  state_set attempts 0
  refresh_desc
  return 0
}

do_reboot() {
  bp_log "Rebooting"
  sync
  /system/bin/reboot 2>/dev/null || setprop sys.powerctl reboot
}

# ---------- status line on the module card ----------

set_desc() {
  prop="$BP_MOD/module.prop"
  [ -f "$prop" ] || return 0
  grep -v '^description=' "$prop" > "$prop.tmp"
  echo "description=$1" >> "$prop.tmp"
  cat "$prop.tmp" > "$prop"
  rm -f "$prop.tmp"
}

refresh_desc() {
  if [ -f "$BP_STATE/gaveup" ]; then
    set_desc "❌ Gave up: the boot problem is not caused by modules or scripts. Check the log."
    return
  fi
  if [ -f "$BP_STATE/last-rescue" ]; then
    lvl=$(grep '^level=' "$BP_STATE/last-rescue" | cut -d= -f2)
    cnt=$(grep '^count=' "$BP_STATE/last-rescue" | cut -d= -f2)
    t=$(grep '^time=' "$BP_STATE/last-rescue" | cut -d= -f2)
    when=$(date -d "@$t" '+%d.%m %H:%M' 2>/dev/null || echo "$t")
    set_desc "⚠️ Rescued $when: $cnt item(s) disabled (level $lvl). Tap Action to restore them."
    return
  fi
  if [ "$(conf_num SYSTEMUI_MONITOR 1 0 1)" = 1 ]; then ui="SystemUI 🟢"; else ui="SystemUI ⚪ off"; fi
  if [ -f "$BP_STATE/baseline" ]; then trust="Setup trusted 🟢"; else trust="Learning setup 🟡"; fi
  set_desc "🛡️ Armed | Boot 🟢 | $ui | $trust"
}
