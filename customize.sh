#!/system/bin/sh
# Bootloop Protector - installer

DATA=/data/adb/bootloop-protector
OLD=/data/adb/modules/YetAnotherBootloopProtector

ui_print " "
ui_print "  Bootloop Protector"
ui_print "  boot loop and SystemUI crash protection"
ui_print " "

if [ -d "$OLD" ] && [ ! -f "$OLD/remove" ]; then
  abort "! Yet Another Bootloop Protector is installed. Uninstall it first."
fi

mkdir -p "$DATA/state"
for f in config allowed-modules.txt allowed-scripts.txt; do
  if [ ! -f "$DATA/$f" ]; then
    cp "$MODPATH/defaults/$f" "$DATA/$f"
    ui_print "- Created $DATA/$f"
  fi
done

# Settings added in newer versions go into an existing config, values stay as they are
for key in $(grep -o '^[A-Z_]*=' "$MODPATH/defaults/config" | tr -d '='); do
  if ! grep -q "^$key=" "$DATA/config"; then
    echo "" >> "$DATA/config"
    grep -B1 "^$key=" "$MODPATH/defaults/config" >> "$DATA/config"
    ui_print "- New setting: $key"
  fi
done

# Take over the allow lists of the old module, then remove everything it left behind
if [ -d /data/adb/YABP ]; then
  for f in allowed-modules.txt allowed-scripts.txt; do
    [ -f "/data/adb/YABP/$f" ] || continue
    sed -e 's/\r$//' -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "/data/adb/YABP/$f" | grep -v '^$' |
      while IFS= read -r entry; do
        if ! grep -Fxq "$entry" "$DATA/$f"; then
          echo "$entry" >> "$DATA/$f"
          ui_print "- Kept old allowed entry: $entry"
        fi
      done
  done
fi
n=0
for f in /data/adb/YABP /data/adb/service.d/.status.sh /data/adb/systemui.monitor.disable \
         /data/adb/.tmp.lock /data/local/tmp/service.log; do
  if [ -e "$f" ]; then
    rm -rf "$f"
    n=$((n + 1))
  fi
done
[ "$n" -gt 0 ] && ui_print "- Removed $n leftover(s) of Yet Another Bootloop Protector"

set_perm_recursive "$MODPATH" 0 0 0755 0644
for f in "$MODPATH"/*.sh; do set_perm "$f" 0 0 0755; done
set_perm_recursive "$DATA" 0 0 0700 0600

ui_print " "
ui_print "- All data lives in $DATA"
ui_print "- After the next boot the module learns your setup."
ui_print "  It becomes trusted after 10 minutes without problems."
ui_print " "
