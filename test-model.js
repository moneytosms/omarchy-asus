// Regression checks for Model.js — run with `node test-model.js`.
//
// Model.js is plain ES5 loaded by QML, so it can be evaluated directly here.
// The fixtures are verbatim output from asusctl 6.3.8 / hyprctl / the sensor
// script on a TUF Gaming F15 (FX507VV); every parser in Model.js reads real
// tool output, so the only useful test is against real tool output.

const fs = require("fs")
const vm = require("vm")
const assert = require("assert")
const path = require("path")

const M = {}
vm.createContext(M)
vm.runInContext(fs.readFileSync(path.join(__dirname, "Model.js"), "utf8"), M)

// ---------------------------------------------------------------- armoury
const ARMOURY = `Multiple asusd interfaces devices found
charge_mode:
  current: [0,1,2]

dgpu_disable:
  current: [(0),1]

gpu_mux_mode:
  current: [(0),1]

nv_dynamic_boost:
  current: 5..[25]..25
  default: 25

nv_temp_target:
  current: 75..[87]..87
  default: 87

panel_overdrive:
  current: [(0),1]

ppt_pl1_spl:
  current: 28..[133]..135
  default: 115

ppt_pl2_sppt:
  current: 28..[135]..135
  default: 135
`

const a = M.parseArmoury(ARMOURY)
assert.equal(a.supported.pptPl1, true)
assert.equal(a.supported.nvTempTarget, true)
assert.equal(a.supported.panelOverdrive, true)
assert.equal(a.values.ppt_pl1_spl, 133)
assert.deepEqual(a.ranges.ppt_pl1_spl, { min: 28, max: 135 })
assert.equal(a.defaults.ppt_pl1_spl, 115)
assert.equal(a.values.gpu_mux_mode, 0)
// "Multiple asusd interfaces devices found" must not be read as an attribute.
assert.equal(a.supported["Multiple asusd interfaces devices found"], undefined)

// The current option is whichever one is parenthesised — matching only the
// first entry made every toggle read as "off" no matter its real state.
assert.equal(M.parseArmouryValue("[(0),1]").value, 0)
assert.equal(M.parseArmouryValue("[0,(1)]").value, 1)
assert.equal(M.parseArmouryValue("[0,1,2]"), null)

// ---------------------------------------------------------------- sensors
const SENSORS = `cpu_temp=63000
fan_cpu=3000
fan_gpu=3100
bat_pct=99
bat_status=Charging
bat_power=8627000
gpu_temp=51
gpu_power=6.66
gpu_util=15
`
const s = M.parseSensors(SENSORS)
assert.equal(s.cpuTemp, 63)      // millidegrees -> C
assert.equal(s.fanCpu, 3000)
assert.equal(s.gpuTemp, 51)
assert.equal(s.gpuPower, 7)
assert.equal(s.batPct, 99)
assert.equal(s.batStatus, "Charging")
assert.ok(Math.abs(s.batPower - 8.627) < 0.001)  // microwatts -> W

// Missing hardware reports nothing rather than a misleading zero.
const empty = M.parseSensors("")
assert.equal(empty.cpuTemp, -1)
assert.equal(empty.gpuTemp, -1)
assert.equal(M.fmtTemp(-1), "—")
assert.equal(M.fmtRpm(0), "off")

// ---------------------------------------------------------------- display
const MONITORS = JSON.stringify([
    { name: "HDMI-A-1", focused: true, width: 1920, height: 1080, refreshRate: 74.973, x: 0, y: 0, scale: 1.25,
      availableModes: ["1920x1080@74.97Hz", "1920x1080@60.00Hz", "1280x720@60.00Hz"] },
    { name: "eDP-1", focused: false, width: 1920, height: 1080, refreshRate: 60.004, x: -1536, y: 0, scale: 1.25,
      availableModes: ["1920x1080@60.00Hz", "1920x1080@144.00Hz"] }
])
const mon = M.parseMonitors(MONITORS)
// The built-in panel wins even when an external monitor has focus.
assert.equal(mon.name, "eDP-1")
assert.deepEqual(mon.rates, [60, 144])
assert.equal(mon.rate, 60)
// Must be the Lua eval form: `hyprctl keyword monitor` is rejected by
// Hyprland's non-legacy (Lua) config parser. Position and scale are repeated
// because hl.monitor replaces the whole rule.
assert.deepEqual(M.monitorCommand(mon, 144), ["hyprctl", "eval",
    'hl.monitor({ output = "eDP-1", mode = "1920x1080@144", position = "-1536x0", scale = 1.25 })'])
assert.equal(M.parseMonitors("not json"), null)
assert.equal(M.parseMonitors("[]"), null)

// ------------------------------------------------------------ hyprmoncfg
// Where the daemon runs, a refresh change must also be saved into its active
// profile or it reverts; where it does not, the runtime change stands alone.
const MONCFG_RUNNING = JSON.stringify({
    schema_version: 1, version: "1.15.0",
    daemon: { running: true },
    active_profile: { name: "MonLeft" }
})
assert.deepEqual(M.parseHyprmoncfgStatus(MONCFG_RUNNING), { managed: true, profile: "MonLeft" })
assert.deepEqual(M.parseHyprmoncfgStatus(JSON.stringify({ daemon: { running: false }, active_profile: { name: "MonLeft" } })),
    { managed: false, profile: "MonLeft" })
// A running daemon with no active profile has nothing to save into — saving
// would be `hyprmoncfg save ""`, so this must not count as managed.
assert.deepEqual(M.parseHyprmoncfgStatus(JSON.stringify({ daemon: { running: true } })),
    { managed: false, profile: "" })
// Binary missing entirely: the status call produces nothing parseable.
assert.deepEqual(M.parseHyprmoncfgStatus(""), { managed: false, profile: "" })
assert.deepEqual(M.parseHyprmoncfgStatus("command not found"), { managed: false, profile: "" })

// ---------------------------------------------------------------- gpu mode
// Polarity per the kernel ABI (sysfs-platform-asus-wmi): gpu_mux_mode is
// 0 = Discrete, 1 = Optimus/Hybrid — the opposite way round to every other
// toggle, so it gets asserted in both directions.
assert.equal(M.gpuModeId(1, 0, true), "standard")   // hybrid, dGPU on demand
assert.equal(M.gpuModeId(1, 1, true), "eco")        // hybrid, dGPU disabled
assert.equal(M.gpuModeId(0, 0, true), "ultimate")   // MUX routed to the dGPU

// A laptop with no MUX never reports the attribute, so mux is only the
// caller's default 0 — which must not be mistaken for discrete mode.
assert.equal(M.gpuModeId(0, 0, false), "standard")
assert.equal(M.gpuModeId(0, 1, false), "eco")

// The mode table has to agree with the reader, or the button that writes a
// mode and the highlight that reads it back disagree after a reboot.
;["eco", "standard", "ultimate"].forEach(function (id) {
    const def = M.gpuModeDef(id)
    assert.equal(M.gpuModeId(def.mux, def.dgpuDisable, true), id)
})

// ------------------------------------------------------------ pending gpu
// asusd reports its queue per attribute, -1 meaning nothing queued. Verbatim
// shape of the busctl round-trip in Model.queuedGpuScript.
assert.deepEqual(M.parseQueuedGpu("gpu_mux_mode=-1\ndgpu_disable=0\n"),
    { gpu_mux_mode: -1, dgpu_disable: 0 })
// A daemon too old to expose the property, or no busctl at all, must read as
// "nothing queued" rather than as a queued 0.
assert.deepEqual(M.parseQueuedGpu(""), { gpu_mux_mode: -1, dgpu_disable: -1 })
assert.deepEqual(M.parseQueuedGpu("gpu_mux_mode=\ndgpu_disable=junk"),
    { gpu_mux_mode: -1, dgpu_disable: -1 })

// Nothing queued -> no pending mode.
assert.equal(M.pendingGpuModeId(1, 0, true, { gpu_mux_mode: -1, dgpu_disable: -1 }), "")
// Queued from Eco back to Standard: dgpu_disable 1 -> 0, mux untouched.
assert.equal(M.pendingGpuModeId(1, 1, true, { gpu_mux_mode: -1, dgpu_disable: 0 }), "standard")
// Queued into Eco from Standard.
assert.equal(M.pendingGpuModeId(1, 0, true, { gpu_mux_mode: -1, dgpu_disable: 1 }), "eco")
// A queued mux change alone still lands on the current dgpu_disable, so
// Standard -> mux 0 is Ultimate, and it must not be read against a default 0.
assert.equal(M.pendingGpuModeId(1, 0, true, { gpu_mux_mode: 0, dgpu_disable: -1 }), "ultimate")
// Queued value that matches the live state is not a pending change.
assert.equal(M.pendingGpuModeId(1, 1, true, { gpu_mux_mode: -1, dgpu_disable: 1 }), "")
// A missing or malformed queue object must not throw.
assert.equal(M.pendingGpuModeId(1, 0, true, null), "")

// ------------------------------------------------------- queueing a mode
const BOTH = { gpuMux: true, dgpuDisable: true }
const NOTHING_QUEUED = { gpu_mux_mode: -1, dgpu_disable: -1 }

// Live Standard. Eco only needs dgpu_disable; Ultimate only needs the mux.
assert.deepEqual(M.gpuModeCommand(M.gpuModeDef("eco"), NOTHING_QUEUED, 1, 0, BOTH),
    ["sh", "-c", "asusctl armoury set dgpu_disable 1"])
assert.deepEqual(M.gpuModeCommand(M.gpuModeDef("ultimate"), NOTHING_QUEUED, 1, 0, BOTH),
    ["sh", "-c", "asusctl armoury set gpu_mux_mode 0"])
// Already there, nothing queued: no command at all.
assert.equal(M.gpuModeCommand(M.gpuModeDef("standard"), NOTHING_QUEUED, 1, 0, BOTH), null)

// The Standard -> Eco -> Ultimate -> Eco walk. After Eco and Ultimate the
// queue holds dgpu_disable=1 and gpu_mux_mode=0 while the firmware still
// reads live Standard. Clicking Eco has to re-queue the mux back to Optimus:
// comparing against the live value would see mux 1 == 1, write nothing, and
// let the queued Discrete from the Ultimate click boot into Ultimate.
const AFTER_ULTIMATE = { gpu_mux_mode: 0, dgpu_disable: 1 }
assert.deepEqual(M.gpuModeCommand(M.gpuModeDef("eco"), AFTER_ULTIMATE, 1, 0, BOTH),
    ["sh", "-c", "asusctl armoury set gpu_mux_mode 1"])
assert.equal(M.pendingGpuModeId(1, 0, true, { gpu_mux_mode: 1, dgpu_disable: 1 }), "eco")

// Going back to the live mode with something queued must cancel that queue,
// not decide there is nothing to do because the firmware already agrees.
assert.deepEqual(M.gpuModeCommand(M.gpuModeDef("standard"), AFTER_ULTIMATE, 1, 0, BOTH),
    ["sh", "-c", "asusctl armoury set gpu_mux_mode 1 && asusctl armoury set dgpu_disable 0"])

// A mode needing both attributes is reachable in one press.
assert.deepEqual(M.gpuModeCommand(M.gpuModeDef("eco"), NOTHING_QUEUED, 0, 0, BOTH),
    ["sh", "-c", "asusctl armoury set gpu_mux_mode 1 && asusctl armoury set dgpu_disable 1"])

// Unsupported attributes are never written: on a mux-less laptop Eco is just
// the dgpu_disable half, and Ultimate has nothing it may legally do.
const NO_MUX = { gpuMux: false, dgpuDisable: true }
assert.deepEqual(M.gpuModeCommand(M.gpuModeDef("eco"), NOTHING_QUEUED, 0, 0, NO_MUX),
    ["sh", "-c", "asusctl armoury set dgpu_disable 1"])
assert.equal(M.gpuModeCommand(M.gpuModeDef("ultimate"), NOTHING_QUEUED, 0, 0, NO_MUX), null)

// ---------------------------------------------------------------- features
// asusctl 6.x names the charge limit ChargeControlEndThreshold; matching only
// on the word "battery" hid the limit slider on models that support it.
const INFO = `Supported Platform Properties:
[
    ChargeControlEndThreshold,
    ThrottlePolicy,
]
Supported Aura Modes:
[
    Static,
    Breathe,
]
`
const f = M.parseSupportedFeatures(INFO)
assert.equal(f.hasBattery, true)
assert.deepEqual(f.auraModes, ["Static", "Breathe"])
assert.equal(M.supportedEffects(f.auraModes).length, 2)

// ---------------------------------------------------------------- fan curves
const pts = M.parseFanPoints("30c:1%,49c:2%,60c:40%")
assert.deepEqual(pts, [{ temp: 30, speed: 1 }, { temp: 49, speed: 2 }, { temp: 60, speed: 40 }])
assert.equal(M.serializeFanPoints(pts), "30c:1%,49c:2%,60c:40%")
// Dragging past a neighbour reorders instead of crossing, and stays in bounds.
const moved = M.moveFanPoint(pts, 0, 200, -5)
assert.deepEqual(moved[moved.length - 1], { temp: 100, speed: 0 })

// ---------------------------------------------------------------- slash
// Verbatim `asusctl slash --list` output (asusctl 6.3.8, ROG Zephyrus G14
// GA403WM). The order matters as much as the names: it is the index space
// asusd reports the active mode in.
const SLASH_LIST = `"Static"
"Bounce"
"Slash"
"Loading"
"BitStream"
"Transmission"
"Flow"
"Flux"
"Phantom"
"Spectrum"
"Hazard"
"Interfacing"
"Ramp"
"GameOver"
"Start"
"Buzzer"
`
const sm = M.parseSlashModes(SLASH_LIST)
assert.equal(sm.length, 16)
assert.equal(sm[0], "Static")
assert.equal(sm[15], "Buzzer")
// The index of a name here is what asusd's mode field carries.
assert.equal(sm.indexOf("Spectrum"), 9)
// Noise (a header line, an error, a blank) never becomes a mode tile.
assert.deepEqual(M.parseSlashModes("Error: no such device\n\n"), [])
assert.deepEqual(M.parseSlashModes(""), [])

// `busctl call ... xyz.ljones.Slash DeviceState`, verbatim.
const st = M.parseSlashState("byyu true 255 0 15\n")
assert.equal(st.available, true)
assert.equal(st.enabled, true)
assert.equal(st.brightness, 255)
assert.equal(st.interval, 0)
assert.equal(st.mode, 15)
assert.equal(sm[st.mode], "Buzzer")
assert.deepEqual(M.parseSlashState("byyu false 100 3 9"),
    { available: true, enabled: false, brightness: 100, interval: 3, mode: 9 })
// No ledbar, or an asusd too old to expose one, must read as unavailable
// rather than as a switched-off ledbar — the panel keeps its last known state
// on `available: false` instead of snapping to a fabricated one.
assert.equal(M.parseSlashState("").available, false)
assert.equal(M.parseSlashState("Unknown object '/xyz/ljones/Slash'").available, false)

// hasSlash matches the full interface name: "Slash" alone is also the name of
// one of the ledbar's own animations.
const SLASH_INFO = `Supported Core Functions:
[
    "xyz.ljones.Platform",
    "xyz.ljones.Aura",
    "xyz.ljones.Slash",
]
`
assert.equal(M.parseSupportedFeatures(SLASH_INFO).hasSlash, true)
assert.equal(M.parseSupportedFeatures(INFO).hasSlash, false)
// The word on its own (here, an animation name) is not a device.
assert.equal(M.parseSupportedFeatures("Supported Aura Modes:\n[\n    Slash,\n]").hasSlash, false)

assert.deepEqual(M.slashModeCommand("Ramp"), ["asusctl", "slash", "--mode", "Ramp"])
assert.deepEqual(M.slashEnableCommand(true), ["asusctl", "slash", "--enable"])
assert.deepEqual(M.slashEnableCommand(false), ["asusctl", "slash", "--disable"])
// Out-of-range values are clamped to the firmware's ranges rather than passed
// through for asusctl to reject.
assert.deepEqual(M.slashBrightnessCommand(999), ["asusctl", "slash", "--brightness", "255"])
assert.deepEqual(M.slashBrightnessCommand(-5), ["asusctl", "slash", "--brightness", "0"])
assert.deepEqual(M.slashIntervalCommand(9), ["asusctl", "slash", "--interval", "5"])

// Every mode asusctl lists has its own description and preview animation, so
// no tile falls back to the "no description for it yet" placeholder.
sm.forEach(function(name) {
    const d = M.slashModeDef(name)
    assert.equal(d.name, name)
    assert.ok(d.tip.indexOf("no description") < 0, name + " has no tooltip copy")
    assert.ok(d.icon.length > 0, name + " has no icon")
})
// A mode from a newer asusctl still gets a usable tile.
const unknown = M.slashModeDef("Wormhole")
assert.equal(unknown.anim, "static")
assert.ok(unknown.tip.indexOf("Wormhole") === 0)

// Preview frames stay in range for every animation, at every phase, and are
// deterministic — the flicker modes must not re-roll between repaints of the
// same frame or they animate into uniform mush.
sm.forEach(function(name) {
    const anim = M.slashModeDef(name).anim
    for (let ph = 0; ph < 1; ph += 0.05) {
        const lv = M.slashPreviewLevels(anim, ph, 20)
        assert.equal(lv.length, 20, name)
        lv.forEach(function(v) {
            assert.ok(v >= 0 && v <= 1 && !isNaN(v), name + " @" + ph + " -> " + v)
        })
        assert.deepEqual(M.slashPreviewLevels(anim, ph, 20), lv, name + " is not deterministic")
    }
})
// Provenance. The firmware animates the bar itself, so the real frames cannot
// be read back and each shape is either watched or guessed. The split is
// asserted so it cannot rot silently: a mode gets confirmed by dropping its
// `guess` flag, and that has to be a deliberate edit, not a drift.
;(function () {
    const confirmed = ["Static", "BitStream", "Phantom", "Interfacing", "Flow", "Spectrum", "Ramp", "GameOver", "Hazard"]
    const guessed = ["Bounce", "Slash", "Loading", "Transmission", "Flux", "Start", "Buzzer"]
    assert.equal(confirmed.length + guessed.length, sm.length, "every listed mode is accounted for")
    confirmed.forEach(function (n) { assert.equal(M.slashModeDef(n).guess, false, n + " is confirmed") })
    guessed.forEach(function (n) { assert.equal(M.slashModeDef(n).guess, true, n + " is only a guess") })
    // A guessed preview says so where the user can see it, not just in a comment.
    assert.ok(M.slashModeDef("Bounce").tip.indexOf("Preview approximate") > 0)
    assert.ok(M.slashModeDef("Phantom").tip.indexOf("Preview approximate") < 0)
})()

// Shapes corrected against the real ledbar (reported from hardware), not
// guessed. Left of the strip is the BOTTOM of the physical bar, right is the
// TOP — a travelling animation running left-to-right runs bottom-to-top.
//
// Flow is not a travelling wave: two points run in from both ends, meet in the
// middle, then head back out. So the frame is symmetric at every phase, and
// the middle is brightest exactly when the ends are dimmest.
;(function () {
    const mid = M.slashPreviewLevels("converge", 0.5, 21)
    // Compared with a tolerance: the two heads are computed from opposite ends
    // so mirrored pairs land ~1e-16 apart, which deepEqual would fail on.
    mid.forEach(function (v, i) {
        assert.ok(Math.abs(v - mid[mid.length - 1 - i]) < 1e-9, "Flow must stay symmetric")
    })
    assert.ok(mid[10] > 0.9, "Flow: the two heads must meet in the middle")
    assert.ok(mid[0] < 0.1 && mid[20] < 0.1, "Flow: ends dark once met")
    const ends = M.slashPreviewLevels("converge", 0, 21)
    assert.ok(ends[0] > 0.9 && ends[20] > 0.9, "Flow: heads start at the ends")
    assert.ok(ends[10] < 0.1, "Flow: middle dark when the heads are apart")
})()

// Spectrum opens with a wipe DOWN from the top before the cycling band. Only
// the band half was implemented at first, which read as starting mid-effect.
;(function () {
    const early = M.slashPreviewLevels("spectrum", 0.05, 20)
    assert.ok(early[19] > 0.9, "Spectrum: the wipe starts at the top")
    assert.ok(early[0] < 0.1, "Spectrum: the bottom is not lit yet")
    const later = M.slashPreviewLevels("spectrum", 0.3, 20)
    const litEarly = early.filter(function (v) { return v > 0.5 }).length
    const litLater = later.filter(function (v) { return v > 0.5 }).length
    assert.ok(litLater > litEarly, "Spectrum: the wipe must travel downwards")
})()

// Ramp climbs towards the top. A bare sawtooth put a hard reset edge mid-bar
// that read as a glitch, so the wrap falls off over a short run instead.
;(function () {
    const f = M.slashPreviewLevels("ramp", 0, 20)
    let maxJump = 0
    for (let i = 1; i < f.length; i++) maxJump = Math.max(maxJump, Math.abs(f[i] - f[i - 1]))
    assert.ok(maxJump < 0.7, "Ramp: no hard sawtooth edge (jump " + maxJump.toFixed(2) + ")")
})()

// Static is the only one fully lit at every phase; the rest actually move,
// which is the whole point of the preview. Checked across the whole loop
// rather than at two arbitrary phases — the slower blinks (Hazard, GameOver)
// hold a frame long enough for any two given samples to land on the same one.
assert.deepEqual(M.slashPreviewLevels("static", 0.4, 3), [1, 1, 1])
sm.filter(function(n) { return M.slashModeDef(n).anim !== "static" }).forEach(function(name) {
    const anim = M.slashModeDef(name).anim
    const frames = new Set()
    for (let ph = 0; ph < 1; ph += 0.02) frames.add(M.slashPreviewLevels(anim, ph, 20).join())
    assert.ok(frames.size > 1, anim + " does not animate")
})

console.log("ok - all Model.js checks passed")
