<p align="center">
  <img src="bootloop-protector.png" alt="Bootloop Protector" width="100%">
</p>

<h1 align="center">Bootloop Protector</h1>

<p align="center">
  A root module that watches every boot and switches off the module that breaks it,
  so you get a working phone back without a computer or a recovery.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/KernelSU-supported-2dd4bf">
  <img src="https://img.shields.io/badge/SukiSU%20Ultra-supported-2dd4bf">
  <img src="https://img.shields.io/badge/APatch-supported-2dd4bf">
  <img src="https://img.shields.io/badge/Magisk-supported-2dd4bf">
  <img src="https://img.shields.io/badge/license-MIT-7ecb35">
</p>

---

## What it does

When a module or a general script stops the phone from starting, crashes the system again
and again, or breaks SystemUI, Bootloop Protector switches off the cause and reboots.
It works on its own - there is nothing to press.

It does not switch off everything at once. It remembers your **trusted setup** and first
switches off only what is **new or changed** - the module you just flashed or updated.
Everything else keeps running.

It needs no internet, no other module and no build tools. It is pure shell plus a WebUI.

## What it detects

| Problem | How it is caught |
|---|---|
| **Boot loop** | The phone restarts before the boot finishes. After 3 failed boots in a row the next boot starts a rescue. |
| **Stuck boot** | The boot animation never ends. After 180 s the phone is rebooted and the boot counts as failed. |
| **Zygote crash loop** | The boot animation starts over without a real reboot. 4 zygote restarts during boot start a rescue at once. |
| **Soft reboot loop** | After the boot, zygote restarts 4 times within 5 minutes. A single soft reboot is normal and ignored. |
| **SystemUI failure** | SystemUI restarts 3 times within 60 s, or stays down for 30 s. Can be switched off. |

All limits can be changed in the WebUI.

## Smart rescue

1. After a good boot the protector records every enabled module and executable general script
   with a fingerprint (version, boot scripts, `system.prop`, `sepolicy.rule` and the files it adds
   to the system). After 10 minutes without problems this becomes the **trusted setup**.
2. **Level 1** switches off only what is new or changed since the trusted setup.
3. If the problem comes back, **level 2** switches off every module and general script, except the
   ones set to **Never disable**.
4. If even that does not help, the problem is not caused by modules. The protector **gives up**
   and stops rebooting, so it can never become the reason for a loop itself.

The protector never switches itself off and remembers exactly what each rescue disabled, so
**Restore** brings back only those items - not the modules you turned off yourself.

## Rescue by hand

- **Volume Up × 3** during the boot animation starts a rescue. Volume Down is left alone on
  purpose: KernelSU and SukiSU use Volume Down × 3 for their own safe mode.
- **Disable all** in the WebUI works like a level 2 rescue.
- **Flash the module zip in TWRP** (or another custom recovery) when the phone cannot boot far
  enough to run the protector. It installs nothing there - it switches off all modules and
  general scripts and records them, so Restore works after the boot.

## WebUI

Open it from the module card in your root manager (in Magisk, with a WebUI app such as KsuWebUI).

- **Status** - protection state, rescue details with Restore / Keep disabled, watchers, actions
- **Modules** - every module and general script with its state (trusted, new, updated,
  disabled by rescue, reboot pending) and a **Never disable** switch
- **Settings** - failed boots, boot timeout, zygote limit, trust time, SystemUI monitor,
  Volume Up rescue
- **Log** - everything the protector did, newest first

The module card in the root manager also shows the state at a glance:
`🛡️ Armed | Boot 🟢 | SystemUI 🟢 | Setup trusted 🟢`.

## Install

1. Uninstall any other bootloop protector first (two of them would fight each other).
   Leftovers of Yet Another Bootloop Protector are cleaned up automatically.
2. Flash the zip in KernelSU, SukiSU Ultra, APatch or Magisk and reboot.
3. Use the phone normally for 10 minutes - the setup becomes trusted.

## Files

Everything lives in one folder, `/data/adb/bootloop-protector`, and survives module updates.
Uninstalling the module removes it.

| File | Content |
|---|---|
| `config` | settings |
| `allowed-modules.txt` | modules set to Never disable |
| `allowed-scripts.txt` | scripts set to Never disable |
| `bp.log` | log, rotated at 512 KB |
| `state/` | boot counter, trusted setup, rescue records |

## Commands

Everything the WebUI does also works from a root terminal:

```sh
# status
su -c 'sh /data/adb/modules/bootloop-protector/bp.sh status'

# modules with their state
su -c 'sh /data/adb/modules/bootloop-protector/bp.sh modules'

# bring back what the last rescue disabled
su -c 'sh /data/adb/modules/bootloop-protector/bp.sh restore'

# trust the current setup right away
su -c 'sh /data/adb/modules/bootloop-protector/bp.sh trust-now'

# read the log
su -c 'cat /data/adb/bootloop-protector/bp.log'
```

Run `bp.sh` without arguments for the full list.

## Limits

- A module that breaks the phone before the root manager runs any script (a broken kernel or
  boot image) cannot be caught - flash the zip in recovery.
- A hard boot loop needs the failed boots to happen first, because the phone restarts before
  anything can react. Lower *Failed boots before a rescue* for a faster reaction.
- Changes made directly to the system partition, outside of modules, are not undone.

## Credits

The idea of counting failed boots comes from
[Yet Another Bootloop Protector](https://github.com/Magisk-Modules-Alt-Repo/YetAnotherBootloopProtector)
by rhythmcache. Bootloop Protector is a new implementation written from scratch.

## License

[MIT](LICENSE) © Tears Burn (nikakvo)
