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
gpu_runtime=active
`
const s = M.parseSensors(SENSORS)
assert.equal(s.cpuTemp, 63)      // millidegrees -> C
assert.equal(s.fanCpu, 3000)
assert.equal(s.gpuTemp, 51)
assert.equal(s.gpuPower, 7)
assert.equal(s.gpuRuntime, "active")
assert.equal(s.batPct, 99)
assert.equal(s.batStatus, "Charging")
assert.ok(Math.abs(s.batPower - 8.627) < 0.001)  // microwatts -> W

// Missing hardware reports nothing rather than a misleading zero.
const empty = M.parseSensors("")
assert.equal(empty.cpuTemp, -1)
assert.equal(empty.gpuTemp, -1)
assert.equal(empty.gpuRuntime, "")
assert.equal(M.fmtTemp(-1), "—")
assert.equal(M.fmtRpm(0), "off")

// A suspended dGPU reports its runtime state without nvidia-smi telemetry.
const sleeping = M.parseSensors("gpu_runtime=suspended\n")
assert.equal(sleeping.gpuRuntime, "suspended")
assert.equal(sleeping.gpuTemp, -1)
assert.equal(sleeping.gpuPower, -1)

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
assert.equal(M.gpuModeId(0, 0), "standard")
assert.equal(M.gpuModeId(0, 1), "eco")
assert.equal(M.gpuModeId(1, 0), "ultimate")

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

console.log("ok - all Model.js checks passed")
