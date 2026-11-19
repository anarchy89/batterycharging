# batterycharging

A tiny bash script to **stop your MacBook from charging** while it's plugged in and **keep the battery in a range you choose**, for **macOS 27+** (and macOS 26.7+), where older tools no longer work.

```bash
batterycharging off   # stop charging: hold at the current %, never charge up
batterycharging to 65 # charge up to 65%, then hold there just like 'off'
batterycharging range  # keep it in a range: below 40%, charge back up to 60%, then hold again
batterycharging range 30 65 # the same with your own range: below 30%, charge back up to 65%
batterycharging maintain 70 # keep it at 70%; macOS tops it back up when it falls below (microcharging)
batterycharging on    # resume charging: restore your previous charge limit

batterycharging status  # what is set right now and what to run next
batterycharging dischargecheck # how much current is flowing out of the battery right now
batterycharging restart # restart a running hold after an update; the charge limit stays put
```

> [!NOTE]
> On **macOS 26.6 and earlier**, use [actuallymentor/battery](https://github.com/actuallymentor/battery) instead. It has more features and works well on those versions.

## Why I made this

I used to simply switch charging off. With the charger connected and charging disabled, the Mac runs from the wall and the battery just sits there, which is as good as taking the battery out. That is what I wanted all along. macOS no longer allows it, so `batterycharging off` is my attempt to get as close to that behaviour as I can. Everything else here, such as `to N`, `range` and `maintain`, is an extra built on top of it.

The reason the old way stopped working:

`battery` and similar tools stop charging by writing the SMC key `CHTE`. The firmware that ships with macOS 27 and the macOS 26.7 update **doesn't have that key anymore**. The SMC reports it as not found, so every write fails.

Apple's replacement, a firmware charge-limit interface (`bfD0`/`bfE0`/`bfF0`), rejects every caller that lacks the private `com.apple.private.iokit.soc-limit` entitlement, root included. Third-party tools can't get that entitlement. (Background: [az-code-lab/ampere](https://github.com/az-code-lab/ampere).)

**What this script does instead:** it drives macOS's own **Manual Charge Limit**, the feature behind *System Settings → Battery → Charge Limit*. System Settings only lets you choose 80–100%, but the underlying preferences accept any value from 1 to 100:

| Setting | Location |
|---|---|
| `MCLFeatureState` (1 = on) | `com.apple.smartcharging.topoffprotection` in `/var/root/Library/Preferences` |
| `mclLimitValue` (percent) | same domain |

After writing them, the script posts the Darwin notification `com.apple.smartcharging.defaultschanged` so the system reloads its settings. **The firmware itself then stops charging at the limit**, including during sleep. Basically it will disable charging, so that if it drops to 79 it will stay there, if it drops to 78 it will stay there. I made this because I was worried about it always force charging back to 80%; wearing the battery out.

### How `off` works

1. Saves your current charge-limit settings (only once, so you can get them back later).
2. Sets the charge limit to your **current battery %**. 
3. Starts a small background loop as root. Every 60 seconds, it checks the battery; if the level has dropped, **it lowers the limit to match**. The limit is never set above the battery, so the Mac runs on wall power and never charges back up.
4. You will notice the charging cable light should turn green (means it thinks its fully charged), if you look for the icon at the top right, it will say power source power adapter and if you open settings / battery it will say Charged to 0% limit.

### Why a hold lets the battery level drop

This is deliberate. batterycharging does not discharge the battery. What it does is allow the level to drop instead of charging it back up, if that is the behaviour you want.

With macOS's own charge limit, the battery is charged back up towards the limit after it has fallen below it. I wanted to avoid those repeated top-ups, so a hold does the opposite: it never charges, and when the battery level goes down, it accepts the lower level as the new place to hold.

That does not mean the battery is drained while it sits on the charger. During a hold the Mac runs on wall power and the battery is left alone, so the level normally stays where it is for hours or days. It only goes down when the battery is really being used:

- **You use the Mac unplugged.** Whatever you use is not charged back when you plug in again.
- **The Mac needs more power than the charger gives**, for example heavy work on a small charger. The battery covers the difference.
- **Slow self-discharge** over a long time on the charger. This is small.

A hold also never leaves its limit below the battery level, because macOS answers that by running the Mac from the battery until the level is back down, even on the charger. This matters in two cases: when you run `batterycharging off` while the Mac is charging, the charge takes a minute or so to stop and the battery can end up a point above where the hold began; and the percentage macOS reports can wobble by a point. In both, the hold raises its limit to match (by two points at most) and holds there. That does not charge the battery; it only avoids draining it. You can check with `batterycharging status` that the Battery and Charge limit lines show the same number, and with `batterycharging dischargecheck` that the current is 0 mA.

What a hold does in each situation:

| Situation | What the hold does |
|---|---|
| Sitting on the charger, nothing changing | Holds. The battery is left alone (`dischargecheck` shows 0 mA) |
| You use the Mac unplugged, then plug back in | Stays at the lower level. It is not charged back up |
| The level slowly falls over days | The limit follows it down, a point at a time |
| You run `off` while the Mac is charging | Charging takes a minute or so to stop, so the battery can end up a point or two higher. The hold settles there within two or three minutes; `dischargecheck` can show a negative number for about a minute on the way |
| The reported percentage wobbles by a point | The limit follows the reading down and back up. Nothing is charged or drained |
| The level jumps by three points or more | Not followed. The limit stays, and macOS brings the battery back down to it by running the Mac from the battery |
| `to 65` ends a point over, at 66% | Holds at 66% |
| A `range` is set and the level falls below its low value | Charges up to the high value, then holds again |
| A `range` is set and the level is above it | Holds where it is; see [How `range` works](#how-range-works) |
| You run `maintain N` | The hold ends. macOS keeps the battery at N% by itself; see [How `maintain` works](#how-maintain-works) |
| The Mac restarts | The charge limit the hold last set (for example 64%) stays in place, so the Mac still will not charge past it. But the hold itself stops: the limit no longer follows the battery down and a range no longer recharges. Start a new hold with `off` or `to N` |

If you would rather have the battery charged back up when it gets low, set a [`range`](#how-range-works). To go back to normal charging at any time, run `batterycharging on`.

> [!WARNING]
> A hold never charges the battery back up. Every drop is permanent until you run `batterycharging on`: slow self-discharge while plugged in, and normal use whenever you unplug. Left long enough, the battery will drain to 0%. Keep an eye on the level and run `batterycharging on` yourself when it gets low, or set [`range`](#how-range-works) to recharge automatically when it gets to the lower limit. The same applies to the hold after `to N`.

### How `to N` works

For when the battery has dropped lower than you'd like (say 30%) and you want to top it up without going back to a full charge. `batterycharging to 65` sets the charge limit to 65%, so the Mac charges up to that level and the firmware stops it there. The background loop checks every 60 seconds and once the target is reached it switches to the same hold as `off`: the limit only follows the battery down. It works whether or not a hold is already active (it replaces the running one) and if you're already at or above N it just holds at the current level.

- **Stopping just short of the target:** if the firmware stops a point or two below the target (say 64% for a target of 65%) and the Mac reports "not charging" on AC power, the loop treats that as done and switches to the hold. Without this, the script would wait for 65% forever and recharge every time the battery dipped.
- **Unplugging during the charge-up:** the script stays in "charge to N" mode and continues when you plug back in.

`on` Stops the loop and restores the settings it saved (it will restore it to your previous limit of 80,85,etc.)

### How `range` works

On its own, a hold only ever follows the battery down, all the way to 0% if you let it. `range` sets a low and a high value: when the battery falls below the low value, it charges back up to the high value and holds again. You set it once and it stays set until you turn it off, so a Mac that lives on the charger looks after itself.

```bash
batterycharging range        # below 40%, charge back up to 60%, then hold again
batterycharging range 25 70  # same, with your own low and high values
batterycharging range 70 25  # the order does not matter: the smaller number is the low value
batterycharging range off    # turn it off
```

- **It does not bring the battery down into the range.** batterycharging does not discharge the battery; it only allows the level to drop instead of charging it back up. So a range only acts at the bottom. If you set `batterycharging range 25 65` while the battery is at 90%, it stays near 90% and drifts down by itself; it is not taken down to 65%. Once it falls below 25% it charges to 65%, and from then on it stays between 25% and 65%. If you want to be in the range sooner, unplug the charger and use the Mac until the battery is down to 65% or lower, then plug it back in; the hold picks up from there. Waiting works just as well. The command tells you when the battery is above or below the range you set.
- **It works together with a hold.** `range` does not start one; start a hold with `off` or `to N` as usual. Without `range`, those commands work exactly as described above. Once it's set, any hold started with `off` or `to N` checks the battery every 60 seconds and, if it is below the low value, does the same thing as `batterycharging to 60`. After the charge-up it goes back to holding.
- **Either order works.** `batterycharging range 25 70` and `batterycharging range 70 25` set the same range: the smaller number is always the low value and the larger one the high value.
- **Invalid values are refused with an error, and nothing is changed.** Both values must be whole numbers from 1 to 100 and different from each other. A negative number, 0, a number above 100, a decimal such as `12.5`, two equal numbers such as `50 50`, or only one number is rejected, and any range you set earlier stays in force.
- **You can set it at any time.** A hold that is already running picks it up within a minute; there is no need to restart it. That includes a recharge in progress: change the range and the charge follows the new high value, and `range off` stops it where it is.
- **Unplugged:** if the battery drops below the low value while unplugged, the limit is raised straight away and the Mac charges to the high value when you plug back in.
- **`on` keeps the setting.** It stops the hold as usual, and the saved range applies again to your next hold. `on` reminds you of this.
- **You are told when it is on.** While `range` is set, `off` and `to N` print a warning that the refill is active, including when a hold is already running. Run `batterycharging range off` first if you want a hold that never charges back up.
- The low value also applies to a hold you start below it: with `range` set, `batterycharging off` at 15% charges up to 60% and holds there.

### How `maintain` works

> [!NOTE]
> I have not tested `maintain` on a real Mac, because I do not need this behaviour myself. If you use it and it does not work, or you do not like how it behaves, [let me know](https://github.com/anarchy89/batterycharging/issues) and I will modify it.

```bash
batterycharging maintain 70   # keep the battery at 70%
batterycharging status        # shows "Maintain: on" and the level
batterycharging maintain 80   # change the level
```

To turn it off, use one of these, depending on what you want next:

```bash
batterycharging on            # back to normal charging; restores your previous charge limit
batterycharging off           # stop maintaining and hold at the current level, without charging back up
```

`maintain` is basically Apple's own Charge Limit, with its usual charge-back-up and run-from-the-battery behaviour, except that you can set it below 80%. System Settings → Battery → Charge Limit only offers 80% to 100%; `maintain` writes the same setting with any value from 1 to 100, and from then on it is Apple's mechanism that keeps the battery there.

`batterycharging maintain 70` keeps the battery at 70%. It sets the charge limit to that level and leaves it there, and macOS does the rest:

- when the battery falls below 70%, macOS charges it back up;
- when the battery is above 70%, macOS runs the Mac from the battery, even on the charger, until it is down to 70%.

> [!WARNING]
> Maintain allows microcharging. Each time the battery falls below the level you set, macOS charges it back up, so the battery gets small top-ups again and again. Those top-ups are what `batterycharging off` avoids. Use `maintain` if you want the battery kept at a fixed level and accept that; use `off` if you want the battery left alone.

How it differs from a hold:

| | Hold (`off`, `to N`) | `maintain N` |
|---|---|---|
| Battery falls below the level | accepts the lower level, never charges back | charges back up to N% (microcharging) |
| Battery is above the level | holds where it is | runs from the battery down to N% |
| Left alone for a long time | drifts down, to 0% unless a `range` is set | stays at N% |
| After a restart | the hold stops until you start a new one | keeps working; nothing needs to run |
| `range` | recharges at the low value | not used |

- **Switching:** `batterycharging off` or `to N` turns maintain off and starts a hold. `batterycharging maintain N` during a hold ends the hold. `batterycharging on` ends either and restores your previous charge limit.
- **Going down a long way:** if the battery is 10 points or more above the level, the command says how far it has to drop and asks before starting, because the Mac will be running from the battery the whole time.
- **How often it tops up is not known.** I have not measured how far the battery has to fall before macOS charges it back up.

### What the charger light tells you

If you charge with a MagSafe cable, the light on its connector shows which state the Mac is in:

| MagSafe light | State | When you see it |
|---|---|---|
| **Green** | Drawing power from the wall, battery not charging | During a hold (`off`, or `to N` once it has reached its level), or when the battery is full |
| **Orange** | Charging the battery | After `batterycharging on`, while `to N` is charging up, or while a `range` is charging back up to its high value |

So after `batterycharging off` the light turns green even though the battery is not full: the Mac runs on wall power and leaves the battery alone. When a range kicks in at its low value, the light turns orange until the high value is reached, then green again.

**The battery reacts later than the light.** After you type a command, the light can change colour before the battery has actually started or stopped charging. Measured on an M3 MacBook Air on macOS 27.2:

| After this | The battery actually | Time taken |
|---|---|---|
| `batterycharging on` | starts charging | about 20 to 45 seconds |
| `batterycharging off`, or `range off` during a recharge | stops charging | about 1 to 2 minutes |
| a `range` reaching its low value | starts charging | within about 2 minutes |

So allow two or three minutes before deciding a command has not worked. During that time the light may already be green while the battery is still charging. `batterycharging dischargecheck` shows what the battery is really doing.

USB-C chargers have no light; use `batterycharging status` instead, which shows `not charging` or `charging` on its Battery line.

## Requirements

- An Apple Silicon MacBook on **macOS 27+** or **macOS 26.7+**
- Admin rights (the script uses `sudo`)

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/anarchy89/batterycharging/main/setup.sh | sh
```

This downloads the latest release, checks that it runs and installs it into `/usr/local/bin`. It asks for your password if that folder needs it. Run it again at any time to reinstall.

### By hand

```bash
# 1. Download the script
curl -fsSL https://github.com/anarchy89/batterycharging/releases/latest/download/batterycharging -o batterycharging

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

### Update

```bash
batterycharging --update
```

This checks the latest release and replaces the installed script if the release is newer. It asks for your password when the folder needs it.

A hold that is already running keeps using the old version until it is restarted. After updating, `--update` tells you so and offers to do it, showing the command it will run:

```
Updated batterycharging 1.0.2 to 1.0.3.
A hold is still running the old version.
Restart it now with the new one? This runs: batterycharging restart [Y/n]
```

`batterycharging restart` swaps the running hold for one from the installed script. The charge limit is not restored in between, so nothing charges, and a `to N` that is still charging up keeps its target. Answer `n` to leave the hold alone and run `batterycharging restart` yourself later. Your `range` setting is kept across an update; there is nothing to set again.

`batterycharging --version` shows what you have.

### Coming from a version before 1.0.8

In 1.0.7 the `auto` command was renamed to `range`, and a setting made with `auto` is not carried over. If you installed before 1.0.8, do not use `--update` for this one step. Turn charging back on, remove everything and install again:

```bash
batterycharging on                                           # 1. stop any hold and restore your charge limit
sudo rm /usr/local/bin/batterycharging                       # 2. remove the old script...
sudo rm -rf "/Library/Application Support/batterycharging"   #    ...and its saved settings
curl -fsSL https://raw.githubusercontent.com/anarchy89/batterycharging/main/setup.sh | sh   # 3. install the latest version
```

Then set it up again: `batterycharging off` or `batterycharging to N` to start a hold, and `batterycharging range` if you want the battery kept in a range.

Run `batterycharging on` first, as shown. If the script is removed while a hold is active, the hold keeps running and the low charge limit stays in place.

`batterycharging --version` shows which version you have; a copy too old to know that command prints a usage line instead, and is also older than 1.0.8. From 1.0.8 onward, `batterycharging --update` is all you need for future releases.

## Usage

```bash
batterycharging off
# Password: ****
# Charging off: holding at 72%. Charge can only go down until 'batterycharging on'.
# Warning: left like this, the battery will eventually drain to 0%. Run 'batterycharging on' when it
# gets low, or set 'batterycharging range' to recharge automatically when it gets to the lower limit.

batterycharging on
# Charging on: previous charge limit restored.
```

To check how much the battery is discharging:

```bash
batterycharging dischargecheck
# Current at the battery, three readings 5 seconds apart:
#   14:37:16       0 mA  not in use: the Mac is running on wall power
#   14:37:21       0 mA  not in use: the Mac is running on wall power
#   14:37:26       0 mA  not in use: the Mac is running on wall power
#   Battery: 57%; AC attached; not charging
```

A negative number means the Mac is running from the battery, even if the menu bar says "Power Source: Power Adapter"; `0 mA` means it is running on wall power and the battery is left alone; a positive number means it is charging. It needs no password.

During a hold it should read `0 mA`. Right after the battery level drops a point it can show a negative number for a while. To check that it has settled:

1. Wait about a minute after the drop.
2. Make sure a hold is on and `batterycharging status` shows the same percentage on its Battery and Charge limit lines.
3. Run `batterycharging dischargecheck`. It should be back to `0 mA`.

macOS only refreshes the reading about every half minute, so the three lines are often identical; if it still shows a negative number, wait and run it again.

To check what's set right now:

```bash
batterycharging status
# batterycharging 1.0.13
#   Battery:       58%, on AC Power, not charging
#   Charge limit:  58%
#   Hold:          on, the limit follows the battery down, unless range is on (see Range for its limits)
#   Range:         on, below 40% a hold charges back up to 60%
#   Maintain:      off
#   'on' restores: 80% charge limit
#
# What you can do:
#   batterycharging on         back to normal charging (80% charge limit)
#   batterycharging to N       charge up to N% now, then hold there
#   batterycharging range off  stop the recharging, so the hold only ever goes down
```

It shows the battery, the charge limit that is set, whether a hold is running, whether `range` or `maintain` is on and which commands make sense next, including how to get back to normal charging. It asks for your password because the charge limit is stored in root's preferences. It also tells you when a hold has stopped at a restart but its limit is still in place.

The raw values it reads are:

```bash
sudo defaults read com.apple.smartcharging.topoffprotection
pmset -g batt
```

## Notes & limitations

- **Reboots:** the firmware keeps the mac os system charge limit across a reboot, so the Mac still won't charge past it. The background loop does **not** restart after a reboot, so the limit stops following the battery down. Run `batterycharging on` and then `batterycharging off` again to start a new hold. The `range` refill also stops working after a reboot until you start a new hold, although the setting itself is kept.
- **System Settings:** while a hold is active, *Battery → Charge Limit* may show an odd value, because the script sets limits below 80%. Don't change it there while holding; use `batterycharging on` instead.
- **Restoring:** `on` restores your previous charge limit (for example 80%, 90%, 95%). If Charge Limit had never been set on your Mac, `on` sets it to 100%, which charges fully just as before; System Settings → Battery then shows a 100% charge limit.
- **Battery calibration (reported by others, not seen here):** macOS occasionally recalibrates the battery, and while it does it is reported to ignore the charge limit and charge to 100%. If that happens during a hold, the limit stays where it was and macOS brings the battery back down afterwards.
- **Optimized Battery Charging (reported by others, not seen here):** it is reported to interfere with charge limits. If the limit is not respected, try turning it off in *System Settings → Battery*.
- State files are kept in `/Library/Application Support/batterycharging/`.
- **The download is not signed.** `setup.sh` and `batterycharging --update` fetch the script from this repository's releases over HTTPS and trust what they get. Each release lists the SHA-256 of its script so you can compare: `shasum -a 256 /usr/local/bin/batterycharging`. The script runs parts of itself as root, so read it first if you prefer; it is short.
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

