# omarchy-asus

A tabbed ASUS laptop control panel for the [Omarchy](https://omarchy.org) bar,
built on [`asusctl`](https://asus-linux.org/). Power profiles, keyboard RGB,
the Zephyrus Slash ledbar, editable fan curves, and firmware limits —
organized like [G-Helper](https://github.com/seerge/g-helper), scoped to what
your specific model actually supports.

| Main | RGB |
|---|---|
| ![Main tab](docs/screenshots/main.png) | ![RGB tab](docs/screenshots/rgb.png) |

| Fan | Advanced |
|---|---|
| ![Fan tab](docs/screenshots/fan.png) | ![Advanced tab](docs/screenshots/advanced.png) |

## Why

The stock single-scroll ASUS panel dumps every `asusctl` feature into one
column regardless of whether your laptop supports it — wattage sliders with
no context, keyboard RGB effects that silently no-op on unsupported hardware,
a fan curve toggle for the master enable that never appears in the UI. This
plugin detects what your specific model reports supporting and only shows
that.

## Features

- **Live sensors** — CPU and GPU temperature, both fan speeds, GPU draw and
  utilisation, battery charge and charge rate, refreshed every 2 seconds while
  the panel is open. The same readings appear in the bar icon's tooltip, so
  "how hot is it right now" needs no click.
- **Main** — performance mode (Quiet/Balanced/Performance, tinted by mode),
  GPU mode (Eco/Standard/Ultimate), screen refresh rate and panel overdrive,
  battery charge limit.
- **RGB** — keyboard lighting, filtered to the aura effects your laptop
  actually reports (`asusctl info --show-supported`), not a fixed list of
  twelve, plus brightness and the awake/boot/sleep power states.
- **Slash** — the lid ledbar on Zephyrus models: every animation `asusctl`
  lists, an animated preview strip that plays whichever one you point at, an
  on/off pair, a 0–255 brightness slider, and the animation interval. On a
  laptop without a ledbar the tab is still there but greyed out and says so,
  rather than vanishing.
- **Fan** — a master "Custom Fan Curves" switch, a per-profile curve editor
  (curves are stored per power profile, so you pick which profile you are
  tuning), draggable curves per fan (CPU/GPU, plus Mid on laptops with a third
  fan) with the live RPM and temperature for that fan alongside, and a
  one-click reset.
- **Advanced** — firmware power limits (PL1/PL2, GPU dynamic boost, GPU temp
  target) with ranges read from the firmware and a "Defaults" button that
  replays the values `asusctl` reports as default. Each control appears only
  if `asusctl armoury list` says your laptop exposes it.
- **Bar icon** — scroll over it to cycle performance modes without opening the
  panel.

### G-Helper parity

This mirrors [G-Helper](https://github.com/seerge/g-helper)'s layout and
feature set where Linux tooling allows it. Where the two diverge:

| G-Helper feature | Status here |
|---|---|
| Slash ledbar | Implemented — see [Slash ledbar](#slash-ledbar) |
| Anime Matrix | Not implemented (no such hardware to test against) |
| CPU boost toggle | Needs root writes to `intel_pstate`/`cpufreq`; `asusctl` exposes no equivalent |
| AutoTDP, FPS limiter, overlay | Windows-only mechanisms |
| Per-key / per-zone RGB | `asusctl` exposes zones only on some models; single-colour effects only for now |
| Automatic AC/battery profile switching | `asusctl` applies its own AC/battery profiles; not duplicated here |

### Slash ledbar

The lid strip on ROG Zephyrus (and some Strix) models, on its own tab. Three
things make it different from every other control here:

- **The mode list is read from `asusctl slash --list`, not hardcoded.** A
  name's *position* in that list is the value `asusd` reports for the active
  mode, so reading the names and the active index from the same source is what
  keeps the highlighted tile honest across `asusctl` versions.
- **`asusctl` has no `slash --get`**, so the current state comes from `asusd`
  over D-Bus. The `xyz.ljones.Slash` interface hangs off the *aura device*
  object, whose path ends in a per-model device id
  (`/xyz/ljones/aura/19b6_3_4`), so the plugin discovers the path rather than
  hardcoding it. It calls `DeviceState` rather than reading the individual
  properties, because the `.Mode` property reads back a stale `0` on
  asusd 6.3.8 whatever the real mode is, while the `DeviceState` tuple
  (`enabled`, `brightness`, `interval`, `mode`) is correct.

- **The preview strip is drawn, not read.** `asusd` exposes no way to read the
  firmware's real frames, so each animation is a stylised impression written by
  hand. It exists so the grid can be picked from by eye instead of by guessing
  what "Interfacing" means, and it tracks the brightness slider and the on/off
  state so those read off it too.

In the preview, **the left end of the strip is the bottom of the physical
ledbar and the right end is the top** — an animation running left to right is
running bottom to top on the lid. Every travelling shape is written against
that mapping.

Why they have to be drawn by hand: the firmware animates the bar entirely on
its own. Once a mode is set, `asusd` sends nothing further — measured at zero
CPU while an animation runs — no LED device appears under `/sys/class/leds`,
and the Slash D-Bus interface carries only mode/brightness/interval/enabled.
There is no frame data to capture anywhere.

So each preview is either **confirmed** — watched on the bar, or read frame by
frame off an ASUS animation capture — or **inferred from the mode's name**.
`Model.js` marks which with a `guess` flag that the tooltip repeats to the
user. Confirmed: Static, BitStream, Phantom, Interfacing, Flow, Spectrum, Ramp,
GameOver, Hazard. Still guesses: Bounce, Slash, Loading, Transmission, Flux,
Start, Buzzer.

Guessing has been wrong every single time it was checked. Flow was written as a
travelling wave when the bar actually runs two points in from the ends to meet
in the middle. Spectrum was missing the wipe it opens with. GameOver was three
full-bar flashes when the real thing is a symmetric sequence — outer quarters
first, then the middle, then the whole bar. Hazard was alternating blocks when
bands actually spread outwards from the centre. If you own one of these
laptops, checking a guessed mode and correcting its entry is the single most
useful contribution to this tab.

### Screen refresh rate

`asusctl` has no display controls, so the refresh buttons drive Hyprland
directly. The built-in `eDP-*` panel is preferred over external monitors, since
this is a laptop-screen feature.

Two details worth knowing:

- Hyprland 0.56 parses its config as Lua, and `hyprctl keyword monitor` is
  rejected against a non-legacy parser. The mode change goes through
  `hyprctl eval "hl.monitor({ ... })"` instead — the same call
  `omarchy-hyprland-monitor-scaling` uses. Position and scale are always
  repeated, because `hl.monitor` replaces the whole rule.
- If [hyprmoncfg](https://github.com/crmne/hyprmoncfg) is installed and its
  daemon is running, it owns monitor configuration and re-applies its active
  saved profile a few seconds after any runtime change — a plain `hl.monitor`
  call silently reverts. The plugin detects this (`hyprmoncfg status --json`)
  and follows the mode change with `hyprmoncfg save <active profile>` so it
  sticks and survives a reboot. The Screen header shows the profile name when
  this is in effect.

  Note that `hyprmoncfg save` snapshots the *whole* current monitor state, not
  just the refresh rate, so it also refreshes that profile's workspace-to-output
  assignments. Without the daemon, the runtime change stands on its own and
  lasts until the Hyprland config is reloaded.

## Development

```bash
node test-model.js   # parser regression checks against real asusctl output
```

## Prerequisites

```bash
# From AUR
yay -S asusctl

# Or from the OGC Arch repo — see https://asus-linux.org for setup
sudo pacman -S asusctl

sudo systemctl enable --now asusd.service
```

## Install

```bash
omarchy plugin add https://github.com/moneytosms/omarchy-asus.git --enable
```

Or clone manually into `~/.config/omarchy/plugins/io.github.moneytosms.asus`
and enable it via the Omarchy plugin menu.

## Remove

```bash
omarchy plugin remove io.github.moneytosms.asus
```

Nothing is written outside the plugin folder and the plugin's own settings
block in `~/.config/omarchy/shell.json`, which Omarchy drops with the plugin.

## Configuration

`~/.config/omarchy/shell.json`, under the plugin's settings:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `showBatteryLimit` | boolean | `true` | Show the battery charge limit section on Main |
| `refreshIntervalSec` | integer | `10` | Poll interval while the panel is open (5–60s) |

## Compatibility

Works with any laptop `asusctl` supports (ROG, TUF, ProArt, Zenbook). Every
section — RGB effects, fan curves, individual firmware attributes — is gated
on what `asusctl` reports for your specific model; unsupported controls don't
appear rather than sitting there doing nothing. The Slash ledbar is the one
exception: it is shown greyed out on hardware without one, since it is a
feature the Zephyrus line is known for and a silent omission reads as a bug.

## Troubleshooting

```bash
# Verify the plugin is detected
omarchy plugin validate ~/.config/omarchy/plugins/io.github.moneytosms.asus

# Check asusd is running
systemctl status asusd

# Check what your model supports
asusctl info --show-supported
asusctl armoury list

# Slash ledbar: is one detected, and what is it doing right now?
asusctl info --show-supported | grep Slash          # xyz.ljones.Slash = yes
asusctl slash --list
busctl --system call xyz.ljones.Asusd \
  "$(busctl --system tree xyz.ljones.Asusd | grep -o '/xyz/ljones/aura/[A-Za-z0-9_]*' | head -1)" \
  xyz.ljones.Slash DeviceState                      # enabled, brightness, interval, mode
```

## License

MIT
