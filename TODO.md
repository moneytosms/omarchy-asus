# TODO: PR / issue triage (branch `review/pr-triage`)

Started 2026-10-04. Nothing has been posted to GitHub yet. Do the GitHub
actions only after the hardware test below passes.

## Security audit (done)

Every PR was audited by a separate subagent for malice: network calls, URLs,
exfiltration, obfuscation, hidden/bidi unicode, writes outside the plugin,
sudo/pkexec, shell injection, appended payloads in binaries, and commit
metadata. **All 7 PRs are clean.** The combined branch diff was rescanned:
no URLs, no encoded strings, no zero-width or bidi chars.

| PR | Author | Malice | Decision |
|---|---|---|---|
| #8 per-AC/battery profiles | sadraalikhah | clean | **merged** (42b14a8) |
| #4 don't wake sleeping dGPU | adamritter | clean | **merged** (03cdb8e) |
| #7 same + BAT* glob | mddavilap | clean | **BAT\* ported** with co-author credit (82c13ae); rest duplicates #4 |
| #5 GPU mapping | adamritter | clean | **idea ported** (`gpuModeAvailable`, 794bb44); rest superseded |
| #2 mux polarity | xJundo | clean | superseded by ec70f05 |
| #3 pending GPU + Slash + PPT | xJundo | clean | not merged; ask for split (below) |
| #9 Cardwire switching | sadraalikhah | clean (PNG verified, no trailing data) | not merged |

## On this branch

- [x] `794bb44` fixes from main:
  - Eco -> Ultimate left `dgpu_disable=1` queued. The kernel refuses `mux=0`
    while the dGPU is off, so the switch silently did nothing. Both
    attributes are now queued. asusd applies the queue sorted by path
    (`dgpu_disable` first), verified in 6.3.8, 6.4.0 and 6.5.0.
  - With Ultimate queued but not rebooted, clicking Eco took two clicks. One
    click now queues both.
  - "Defaults" only applied PL1. The other 3 writes were dropped because
    `actionProc` was already running. Armoury writes now go through a queue.
  - Eco was clickable on mux-only laptops and wrote nothing. It is now
    disabled with a reason.
- [x] Merged PR #8, PR #4
- [x] BAT\* glob (PR #7), plus `nvidia-smi` also polled when
  `runtime_status=unsupported` (runtime PM off, card never sleeps), so
  telemetry doesn't vanish on those machines
- [x] `node test-model.js` passes. Qt 6.11 `qmllint` reports no syntax
  errors. The sensor script runs clean in dash/sh/bash and was tested
  against a fake sysfs for active/suspended/suspending/resuming/unsupported
- [x] Final review subagent on the combined diff. Merge is clean and main's
  GPU logic is intact. One MAJOR finding (also on main): if the mux write
  failed during Ultimate -> Eco, the Eco marker stuck forever and the panel
  showed Eco pending. Now fixed: the marker is dropped when no mux switch is
  queued and no writes are in flight (needs asusd >= 6.3.8 `QueuedGpuValue`).

## Hardware test on Omarchy (you)

The branch must be pushed first (`git push -u origin review/pr-triage`). The
installed plugin is a git clone, so switch it in place:

```bash
cd ~/.config/omarchy/plugins/io.github.moneytosms.asus
git fetch origin review/pr-triage && git switch review/pr-triage
asusctl --version; node test-model.js
# back to normal afterwards: git switch main
```

Then reload the shell and check each:

- [ ] Panel loads at all (the new `Quickshell.Services.UPower` import)
- [ ] Panel still loads with upower stopped:
      `sudo systemctl stop upower` -> reload shell -> `sudo systemctl start upower`
- [ ] **Profiles (#8):** on AC pick Quiet. `asusctl profile get` shows
      `AC profile Quiet` and the battery profile unchanged. Unplug, pick
      Balanced. Battery profile = Balanced, AC still Quiet. Replug and asusd
      switches to Quiet. Scrolling on the bar icon does the same.
- [ ] **Sensors (#4/#7):** in Standard mode with the dGPU idle, the GPU tile
      shows "Sleeping", and the card stays asleep while the panel is open:
      `watch -n1 cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status`
      (find your address with `lspci -D | rg -i nvidia`).
      Open question from the audit: does a 2s poll of an *active* card stop
      it from ever autosuspending while the panel is open?
- [ ] Run a GPU app. The tile switches to temp/fan/util and GPU POWER shows.
- [ ] Battery tile shows (matters if your battery is BAT1)
- [ ] **Defaults:** move PL1 and PL2 sliders, click Defaults, and all 4 values
      return (`asusctl armoury list`)
      Note: on asusctl 6.4+ PPT sliders need profile tuning on (see below)
- [ ] **GPU mode:** check each and confirm with
      `busctl get-property xyz.ljones.Asusd /xyz/ljones/asus_armoury/{gpu_mux_mode,dgpu_disable} xyz.ljones.AsusArmoury QueuedGpuValue`
  - [ ] Standard -> Eco: queues `dgpu_disable=1`, reboot, Eco
  - [ ] Eco -> Ultimate: queues `dgpu_disable=0` **and** `gpu_mux_mode=0`, ONE reboot, Ultimate
  - [ ] Ultimate -> Eco: notice says "Restart twice". Reboot, then
        `dgpu_disable=1` is queued automatically. Reboot, Eco.
  - [ ] Queue Ultimate, then click Standard before rebooting: nothing pending
  - [ ] Click the current mode again: no writes, no notice
- [ ] Brightness keys work after every switch back to Standard/Eco
- [ ] Failure recovery: in Ultimate, `sudo systemctl stop asusd`, click Eco
      (the write fails), start asusd, reopen the panel. The "Restart twice"
      notice must disappear and
      `ls ~/.local/state/omarchy-asus-eco-pending` must be gone.
- [ ] Defaults with 4 PPT attrs: all 4 land. This confirms the armoury queue
      drains (relies on Process `running` being false by the time
      `Qt.callLater` runs).

If everything passes: merge into main and bump `manifest.json` version.

## GitHub actions (after the hardware test passes)

- [ ] Merge: push `main` with the branch merged. Then #8 and #4 auto-close as
      merged (their commits are in main).
- [ ] #7: comment "BAT\* glob merged in 82c13ae with credit; GPU part
      duplicated #4, which is merged". Then close.
- [ ] #5: thank the author. The polarity and queue display were already on
      main (ec70f05, 0882f10). The `gpuModeAvailable` idea is merged in
      794bb44. Close. Note: always queuing both attrs is unsafe for running
      Ultimate -> Eco on asusd 6.4 (`dgpu_disable` is applied first and
      refused).
- [ ] #2: thank xJundo (they pinged twice). Fixed independently in ec70f05.
      Close. Close issue #1 referencing ec70f05.
- [ ] #3: ask xJundo to resubmit as 3 PRs on current main:
  - Slash ledbar tab: wanted. Fix: setters need an `actionProc.running`
    guard, or should use the armoury-style queue. It also fails silently on
    asusctl < 6.3.9.
  - "Reboot now" button: wanted, but it needs a confirm step (one click
    currently closes everything and reboots).
  - PPT tuning: rework. `asusctl profile tuning true` fails when no custom fan
    curve is enabled ("Custom fan curve is required"), and the error is
    swallowed. Enabling it also rewrites all PPT/NV limits for that
    profile and power source. Show a visible tuning toggle instead of
    enabling it silently.
  - Drop the polarity commit (already on main).
- [ ] #9: leave a review asking to keep it as a fork/optional backend:
      a third-party Cardwire dependency, Eco/Standard disabled without
      it, a marker with no reader (self-declared), and it duplicates #8. Close or
      leave as draft.

## Issues

- [ ] #1: close (fixed by ec70f05)
- [ ] #6 CPU boost toggle: valid request; decide the approach:
  - read state unprivileged (`/sys/devices/system/cpu/cpufreq/boost` on AMD,
    `intel_pstate/no_turbo` on Intel)
  - write via opt-in `pkexec` (password prompt, not persistent), and
  - document a `systemd-tmpfiles` line for persistence
  - avoid installing polkit rules (breaks "nothing written outside plugin")

## Follow-ups (not started)

- [ ] **PPT sliders broken on asusctl 6.4+**: 6.4 stores the value without
      applying it, and 6.5 errors when profile tuning is off. Add a tuning
      toggle on Advanced reading `asusctl profile tuning`, and surface the
      fan-curve requirement.
- [ ] Other `actionProc` setters (aura, LEDs, battery limit, fan curves) still
      drop a click made while another action runs. Consider routing them
      through the queue.
- [ ] On asusd 6.5 the Ultimate -> Eco two-reboot chain is unnecessary
      (6.5's shutdown helper orders writes by dependency, e0abda4b). Keep it
      for 6.4 compatibility, or check the version.
- [ ] README: state the minimum asusctl version (the `--ac`/`--battery` flags
      need >= 6.3.8; Slash subcommands need >= 6.3.9).

- [ ] Review nits (cosmetic, self-heal): the 10s refresh can read a
      half-written GPU queue and flicker for one tick. The GPU tile shows "—"
      when the card is bound to nouveau (no nvidia-smi). If the first of a
      pair of GPU writes succeeds and the second fails, the UI shows the
      target mode until the next refresh.

## Cleanup

```bash
git branch -D pr-2 pr-3 pr-4 pr-5 pr-7 pr-8 pr-9   # local PR refs
```
