## v1.2

- The WebUI opens fast again on a quick reopen: no more waiting about 8 seconds for the status

## v1.1

- The WebUI opens much faster: status and settings show up first, and the module list
  needs far less work per module
- Log: auto refresh no longer jumps back to the top while you scroll through older lines
- Log: new copy button
- Log: new save button - writes the log with a short report (version, phone, root manager,
  settings, rescue state, modules) to the Download folder, handy for bug reports
- Flashing the zip in recovery now resets the boot counter, so the first boot after it
  does not start another rescue
- A rescue records each item before switching it off, so Restore never misses one

## v1.0

First release.

- Catches boot loops, stuck boots, zygote crash loops, soft reboot loops and SystemUI failures
- Smart rescue: first switches off only the modules and scripts that are new or changed since your trusted setup, everything only if that does not help
- Gives up instead of rebooting forever when the problem is not caused by modules
- Restore brings back exactly what a rescue disabled
- Never disable switch for modules and scripts that must always keep running
- Volume Up × 3 during the boot animation starts a rescue by hand
- Flash the zip in TWRP to switch off all modules when the phone cannot boot at all
- WebUI with Status, Modules, Settings and Log tabs, plus a full help page
- Status on the module card in the root manager
- No internet, all data in one folder: /data/adb/bootloop-protector
- Cleans up the leftovers of Yet Another Bootloop Protector on install
