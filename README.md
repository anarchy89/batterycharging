# batterycharging

A tiny bash script to **stop your MacBook from charging** while it's plugged in, for **macOS 27+** (and macOS 26.7+), where older tools no longer work.

```bash
batterycharging off   # stop charging: hold at the current %, never charge up
batterycharging on    # resume charging: restore your previous charge limit
```

> [!NOTE]
> On **macOS 26.6 and earlier**, use [actuallymentor/battery](https://github.com/actuallymentor/battery) instead. It has more features and works well on those versions.

## Why this exists

`battery` and similar tools stop charging by writing the SMC key `CHTE`. The firmware that ships with macOS 27 and the macOS 26.7 update **doesn't have that key anymore**. The SMC reports it as not found, so every write fails.

Apple's replacement, a firmware charge-limit interface (`bfD0`/`bfE0`/`bfF0`), rejects every caller that lacks the private `com.apple.private.iokit.soc-limit` entitlement, root included. Third-party tools can't get that entitlement. (Background: [az-code-lab/ampere](https://github.com/az-code-lab/ampere).)

**What this script does instead:** it drives macOS's own **Manual Charge Limit**, the feature behind *System Settings → Battery → Charge Limit*. System Settings only lets you choose 80–100%, but the underlying preferences accept any value from 1 to 100:

| Setting | Location |
|---|---|
| `MCLFeatureState` (1 = on) | `com.apple.smartcharging.topoffprotection` in `/var/root/Library/Preferences` |
| `mclLimitValue` (percent) | same domain |

After writing them, the script posts the Darwin notification `com.apple.smartcharging.defaultschanged` so the system reloads its settings. **The firmware itself then stops charging at the limit**, including during sleep.

### How `off` works

1. Saves your current charge-limit settings (only once, so you can get them back later).
2. Sets the charge limit to your **current battery %**.
3. Starts a small background loop as root. Every 60 seconds it checks the battery and, if the level has dropped, **lowers the limit to match**. The limit only ever goes down, so the Mac runs on wall power and never charges back up.

`on` stops the loop and restores the settings it saved.

## Requirements

- An Apple Silicon MacBook on **macOS 27+** or **macOS 26.7+**
- Admin rights (the script uses `sudo`)

## Installation

```bash
# 1. Download the script
curl -fsSL https://raw.githubusercontent.com/anarchy89/batterycharging/main/batterycharging -o batterycharging

# 2. Make it executable
chmod +x batterycharging

# 3. Move it somewhere on your PATH
sudo mkdir -p /usr/local/bin
sudo mv batterycharging /usr/local/bin/
```

Check that it installed:

```bash
which batterycharging   # -> /usr/local/bin/batterycharging
```

You can also clone the repo and copy the file:

```bash
git clone https://github.com/anarchy89/batterycharging.git
cd batterycharging
chmod +x batterycharging
sudo cp batterycharging /usr/local/bin/
```

## Usage

```bash
batterycharging off
# Password: ****
# Charging off: holding at 72%. Charge can only go down until 'batterycharging on'.

batterycharging on
# Charging on: previous charge limit restored.
```

To check what's set right now:

```bash
sudo defaults read com.apple.smartcharging.topoffprotection
pmset -g batt
```

## Notes & limitations

- **Reboots:** the firmware keeps the charge limit across a reboot, so the Mac still won't charge past it. The background loop does **not** restart after a reboot, so the limit stops following the battery down. Run `batterycharging on` and then `batterycharging off` again to start a new hold.
- **System Settings:** while a hold is active, *Battery → Charge Limit* may show an odd value, because the script sets limits below 80%. Don't change it there while holding; use `batterycharging on` instead.
- **Restoring:** `on` restores your previous charge limit (for example 80%, 90%, 95%). If Charge Limit had never been set on your Mac, `on` removes the settings the script added, so it's back to how it was.
- State files are kept in `/Library/Application Support/batterycharging/`.
- Apple can change these internals in any update.

## Uninstall

```bash
batterycharging on                                   # restore your charge limit first
sudo rm /usr/local/bin/batterycharging
sudo rm -rf "/Library/Application Support/batterycharging"
```

## Credits

- [az-code-lab/ampere](https://github.com/az-code-lab/ampere): research into the `CHTE` removal and the Manual Charge Limit workaround
- [actuallymentor/battery](https://github.com/actuallymentor/battery): the original tool for older macOS versions

## Disclaimer

Use at your own risk. This script changes undocumented system settings. It is not affiliated with or endorsed by Apple.

## License

MIT

