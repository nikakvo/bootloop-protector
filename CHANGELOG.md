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
