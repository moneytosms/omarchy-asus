// Model.js — asusctl v6.x command wrappers and data parsing

// ============================================================
// Effect definitions
// ============================================================
// `auraName` matches the strings asusctl reports under "Supported Aura
// Modes:" (from `asusctl info --show-supported`) — used to hide effects the
// current hardware doesn't actually support, instead of listing all twelve
// regardless of model.
var effects = [
    { id: "static",        name: "Static",        auraName: "Static",       icon: "\u{F05A8}", params: ["color"],
      tip: "One steady colour across the keyboard." },
    { id: "breathe",       name: "Breathe",       auraName: "Breathe",      icon: "\u{F01C8}", params: ["color", "color2", "speed"],
      tip: "Fades slowly between two colours." },
    { id: "pulse",         name: "Pulse",         auraName: "Pulse",        icon: "\u{F04DA}", params: ["color"],
      tip: "Sharp on/off throb in one colour." },
    { id: "rainbow-cycle", name: "Rainbow Cycle", auraName: "RainbowCycle", icon: "\u{F0764}", params: ["speed"],
      tip: "Whole keyboard shifts through the spectrum together." },
    { id: "rainbow-wave",  name: "Rainbow Wave",  auraName: "RainbowWave",  icon: "\u{F053E}", params: ["speed", "direction"],
      tip: "Rainbow sweeps across the keys in one direction." },
    { id: "stars",         name: "Stars",         auraName: "Stars",        icon: "\u{F0165}", params: ["color", "color2", "speed"],
      tip: "Random keys twinkle between two colours." },
    { id: "rain",          name: "Rain",          auraName: "Rain",         icon: "\u{F0276}", params: ["speed"],
      tip: "Streaks fall down the keyboard." },
    { id: "highlight",     name: "Highlight",     auraName: "Highlight",    icon: "\u{F030D}", params: ["color", "speed"],
      tip: "Only the key you press lights up." },
    { id: "laser",         name: "Laser",         auraName: "Laser",        icon: "\u{F0330}", params: ["color", "speed"],
      tip: "A pressed key fires a beam across the row." },
    { id: "ripple",        name: "Ripple",        auraName: "Ripple",       icon: "\u{F053E}", params: ["color", "speed"],
      tip: "A pressed key sends rings outward." },
    { id: "comet",         name: "Comet",         auraName: "Comet",        icon: "\u{F0361}", params: ["color"],
      tip: "A lit streak runs across the keyboard and fades." },
    { id: "flash",         name: "Flash",         auraName: "Flash",        icon: "\u{F0192}", params: ["color"],
      tip: "Brief full-keyboard flashes." }
]

function supportedEffects(auraModes) {
    if (!auraModes || auraModes.length === 0) return effects
    return effects.filter(function(e) { return auraModes.indexOf(e.auraName) >= 0 })
}

var speeds = ["low", "med", "high"]
var speedLabels = { low: "Slow", med: "Medium", high: "Fast" }
var directions = ["up", "down", "left", "right"]

function buildAuraCommand(effectId, params) {
    var cmd = ["asusctl", "aura", "effect", effectId]
    var effect = null
    for (var i = 0; i < effects.length; i++) { if (effects[i].id === effectId) { effect = effects[i]; break } }
    if (!effect) return cmd
    for (var j = 0; j < effect.params.length; j++) {
        var p = effect.params[j], val = params[p]
        if (val === undefined || val === null || val === "") continue
        if (p === "color")  { cmd.push("--colour"); cmd.push(String(val)) }
        if (p === "color2") { cmd.push("--colour2"); cmd.push(String(val)) }
        if (p === "speed")  { cmd.push("--speed"); cmd.push(String(val)) }
        if (p === "direction") { cmd.push("--direction"); cmd.push(String(val)) }
    }
    return cmd
}

// ============================================================
// Profile
// ============================================================
function profileIcon(name) {
    var n = String(name || "").toLowerCase()
    if (n.indexOf("quiet") >= 0 || n.indexOf("silent") >= 0) return "\u{F032A}"
    if (n.indexOf("balanced") >= 0) return "\u{F029A}"
    if (n.indexOf("performance") >= 0 || n.indexOf("turbo") >= 0) return "\u{F04C5}"
    return "\u{F0244}"
}

// G-Helper tints each performance mode; the same three-colour language is
// reused here so the active profile reads at a glance from the bar icon
// and the mode buttons.
// Tooltip copy for the three throttle policies. Says what each one does to
// fans and power rather than restating its name.
function profileDescription(name) {
    var n = String(name || "").toLowerCase()
    if (n.indexOf("quiet") >= 0 || n.indexOf("silent") >= 0)
        return "Lowest power limits and fan speeds.\nQuietest and coolest, longest battery, slowest under load."
    if (n.indexOf("balanced") >= 0)
        return "Default policy. Power and fans scale with load.\nWhat you want for everyday use."
    if (n.indexOf("performance") >= 0 || n.indexOf("turbo") >= 0)
        return "Highest power limits and fan speeds.\nLoud and hot, but the best sustained performance."
    return "Set the platform throttle policy to " + name + "."
}

function profileColor(name) {
    var n = String(name || "").toLowerCase()
    if (n.indexOf("quiet") >= 0 || n.indexOf("silent") >= 0) return "#44aaff"
    if (n.indexOf("balanced") >= 0) return "#44cc66"
    if (n.indexOf("performance") >= 0 || n.indexOf("turbo") >= 0) return "#ff6644"
    return "#888888"
}

function profileLabel(name) {
    var n = String(name || "").toLowerCase()
    if (n.indexOf("quiet") >= 0 || n.indexOf("silent") >= 0) return "Quiet"
    if (n.indexOf("balanced") >= 0) return "Balanced"
    if (n.indexOf("performance") >= 0 || n.indexOf("turbo") >= 0) return "Performance"
    return name || "\u2014"
}

function parseCurrentProfile(raw) {
    var text = String(raw || "").trim()
    var idx = text.indexOf("Active profile:")
    if (idx >= 0) { var fl = text.substring(idx + 16).trim().split("\n")[0].trim(); if (fl) return fl }
    var lines = text.split("\n")
    if (lines.length > 0) { var parts = lines[0].trim().split(/\s+/); if (parts.length > 0) return parts[0] }
    return ""
}

function parseProfiles(raw) {
    var text = String(raw || "").trim()
    var r = { ac: "", battery: "" }
    var lines = text.split("\n")
    for (var i = 0; i < lines.length; i++) {
        var l = lines[i].trim()
        if (l.indexOf("AC profile") >= 0) r.ac = l.replace("AC profile", "").trim()
        if (l.indexOf("Battery profile") >= 0) r.battery = l.replace("Battery profile", "").trim()
    }
    return r
}

// ============================================================
// Feature detection
// ============================================================
function parseSupportedFeatures(raw) {
    var text = String(raw || "")
    return {
        hasAura: text.indexOf("Aura") >= 0,
        hasFanCurve: text.indexOf("FanCurves") >= 0,
        // asusctl 6.x reports the charge limit as a platform property named
        // ChargeControlEndThreshold rather than anything containing "battery",
        // so matching only on the word hid the limit slider on models that do
        // support it.
        hasBattery: text.indexOf("ChargeControlEndThreshold") >= 0 || text.indexOf("battery") >= 0 || text.indexOf("Battery") >= 0,
        hasProfile: text.indexOf("Platform") >= 0,
        hasAniMe: text.indexOf("anime") >= 0,
        auraModes: parseListSection(text, "Supported Aura Modes:")
    }
}

// Pulls a bracketed list section out of `asusctl info --show-supported`, e.g.
//   Supported Aura Modes:
//   [
//       Static,
//       Breathe,
//   ]
// -> ["Static", "Breathe"]
function parseListSection(text, header) {
    var idx = text.indexOf(header)
    if (idx < 0) return []
    var rest = text.substring(idx + header.length)
    var open = rest.indexOf("[")
    var close = rest.indexOf("]")
    if (open < 0 || close < 0 || close < open) return []
    return rest.substring(open + 1, close).split(",")
        .map(function(s) { return s.trim() })
        .filter(function(s) { return s.length > 0 })
}

// ============================================================
// Battery
// ============================================================
function parseBatteryInfo(raw) {
    var text = String(raw || "").trim()
    var r = { limit: 100 }
    var m = text.match(/(\d+)%/)
    if (m) r.limit = parseInt(m[1])
    return r
}

// ============================================================
// Fan curves — parse per-fan data from `asusctl fan-curve --get-enabled`
// and `asusctl fan-curve --mod-profile <name>`
// ============================================================
function parseFanCurves(raw) {
    var text = String(raw || "")
    var result = { cpuEnabled: false, gpuEnabled: false, midEnabled: false, hasMid: false, cpuPoints: [], gpuPoints: [], midPoints: [] }

    // Parse enabled state: "CPU: enabled: false, 40c:6%,..."
    var lines = text.split("\n")
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim()
        if (line.indexOf("CPU:") >= 0) {
            result.cpuEnabled = line.indexOf("enabled: true") >= 0
            // Extract curve points after the comma
            var idx = line.indexOf(",")
            if (idx >= 0) {
                var curveStr = line.substring(idx + 1).trim()
                result.cpuPoints = parseFanPoints(curveStr)
            }
        }
        if (line.indexOf("GPU:") >= 0) {
            result.gpuEnabled = line.indexOf("enabled: true") >= 0
            var idx2 = line.indexOf(",")
            if (idx2 >= 0) {
                var curveStr2 = line.substring(idx2 + 1).trim()
                result.gpuPoints = parseFanPoints(curveStr2)
            }
        }
        if (line.indexOf("MID:") >= 0) {
            result.hasMid = true
            result.midEnabled = line.indexOf("enabled: true") >= 0
            var idx3 = line.indexOf(",")
            if (idx3 >= 0) {
                var curveStr3 = line.substring(idx3 + 1).trim()
                result.midPoints = parseFanPoints(curveStr3)
            }
        }
    }

    // Also parse detailed curve from `fan-curve --mod-profile` output
    // Format: pwm: (2, 17, 30, ...), temp: (50, 65, 69, ...)
    for (var j = 0; j < lines.length; j++) {
        var ln = lines[j].trim()
        if (ln.indexOf("fan: CPU") >= 0) {
            // Look ahead for pwm and temp lines
            for (var k = j + 1; k < Math.min(j + 5, lines.length); k++) {
                var pline = lines[k].trim()
                if (pline.indexOf("pwm:") >= 0) {
                    var pwms = pline.replace("pwm:", "").replace(/[()]/g, "").split(",").map(function(s) { return parseInt(s.trim()) }).filter(function(n) { return !isNaN(n) })
                    // Find matching temp line
                    for (var t = k + 1; t < Math.min(k + 3, lines.length); t++) {
                        var tline = lines[t].trim()
                        if (tline.indexOf("temp:") >= 0) {
                            var temps = tline.replace("temp:", "").replace(/[()]/g, "").split(",").map(function(s) { return parseInt(s.trim()) }).filter(function(n) { return !isNaN(n) })
                            result.cpuPoints = []
                            for (var m = 0; m < Math.min(pwms.length, temps.length); m++) {
                                result.cpuPoints.push({ temp: temps[m], speed: Math.round(pwms[m] / 255 * 100) })
                            }
                            break
                        }
                    }
                    break
                }
            }
        }
        if (ln.indexOf("fan: GPU") >= 0) {
            for (var k2 = j + 1; k2 < Math.min(j + 5, lines.length); k2++) {
                var pline2 = lines[k2].trim()
                if (pline2.indexOf("pwm:") >= 0) {
                    var pwms2 = pline2.replace("pwm:", "").replace(/[()]/g, "").split(",").map(function(s) { return parseInt(s.trim()) }).filter(function(n) { return !isNaN(n) })
                    for (var t2 = k2 + 1; t2 < Math.min(k2 + 3, lines.length); t2++) {
                        var tline2 = lines[t2].trim()
                        if (tline2.indexOf("temp:") >= 0) {
                            var temps2 = tline2.replace("temp:", "").replace(/[()]/g, "").split(",").map(function(s) { return parseInt(s.trim()) }).filter(function(n) { return !isNaN(n) })
                            result.gpuPoints = []
                            for (var m2 = 0; m2 < Math.min(pwms2.length, temps2.length); m2++) {
                                result.gpuPoints.push({ temp: temps2[m2], speed: Math.round(pwms2[m2] / 255 * 100) })
                            }
                            break
                        }
                    }
                    break
                }
            }
        }
        if (ln.indexOf("fan: MID") >= 0) {
            result.hasMid = true
            for (var k3 = j + 1; k3 < Math.min(j + 5, lines.length); k3++) {
                var pline3 = lines[k3].trim()
                if (pline3.indexOf("pwm:") >= 0) {
                    var pwms3 = pline3.replace("pwm:", "").replace(/[()]/g, "").split(",").map(function(s) { return parseInt(s.trim()) }).filter(function(n) { return !isNaN(n) })
                    for (var t3 = k3 + 1; t3 < Math.min(k3 + 3, lines.length); t3++) {
                        var tline3 = lines[t3].trim()
                        if (tline3.indexOf("temp:") >= 0) {
                            var temps3 = tline3.replace("temp:", "").replace(/[()]/g, "").split(",").map(function(s) { return parseInt(s.trim()) }).filter(function(n) { return !isNaN(n) })
                            result.midPoints = []
                            for (var m3 = 0; m3 < Math.min(pwms3.length, temps3.length); m3++) {
                                result.midPoints.push({ temp: temps3[m3], speed: Math.round(pwms3[m3] / 255 * 100) })
                            }
                            break
                        }
                    }
                    break
                }
            }
        }
    }

    return result
}

// Serializes curve points back into asusctl's --data format: "30c:1%,49c:2%,...".
function serializeFanPoints(points) {
    return points.map(function(p) { return Math.round(p.temp) + "c:" + Math.round(p.speed) + "%" }).join(",")
}

// Moves point[index] to a new temp/speed, clamped to bounds and kept sorted
// by temp (dragging past a neighbor swaps order rather than crossing it).
function moveFanPoint(points, index, temp, speed) {
    var pts = points.map(function(p) { return { temp: p.temp, speed: p.speed } })
    if (index < 0 || index >= pts.length) return pts
    pts[index].temp = clamp(Math.round(temp), 30, 100)
    pts[index].speed = clamp(Math.round(speed), 0, 100)
    pts.sort(function(a, b) { return a.temp - b.temp })
    return pts
}

function parseFanPoints(str) {
    var points = []
    var parts = str.split(/[,;\s]+/)
    for (var i = 0; i < parts.length; i++) {
        var p = parts[i].replace(/[c%]/g, "").trim()
        var kv = p.split(/[:\s]+/)
        if (kv.length >= 2) {
            var temp = parseInt(kv[0]), speed = parseInt(kv[1])
            if (!isNaN(temp) && !isNaN(speed)) points.push({ temp: temp, speed: speed })
        }
    }
    return points
}

// ============================================================
// Armoury / Firmware
// ============================================================
// Walks the whole `asusctl armoury list` output once and returns everything
// the panel needs about every attribute:
//
//   attr_name:
//     current: 28..[133]..135
//     default: 115
//
// -> supported.attr_name = true, values.attr_name = 133,
//    ranges.attr_name = {min:28,max:135}, defaults.attr_name = 115
//
// Toggles ("[(0),1]") land in values as 0/1 with no range. Doing this in one
// pass here keeps Panel.qml free of the per-attribute if-chain it used to
// carry, so adding an attribute is a one-line change at the call site.
function parseArmoury(raw) {
    var lines = String(raw || "").split("\n")
    var out = { supported: {}, values: {}, ranges: {}, defaults: {} }
    var cur = ""
    for (var i = 0; i < lines.length; i++) {
        var l = lines[i].trim()
        if (l.length === 0 || l.indexOf(":") < 0) continue
        if (l.indexOf("Multiple") >= 0 || l.indexOf("devices") >= 0) continue

        if (l.indexOf("current:") === 0) {
            if (!cur) continue
            var p = parseArmouryValue(l.substring(8).trim())
            if (p) {
                out.values[cur] = p.value
                if (p.type === "range") out.ranges[cur] = { min: p.min, max: p.max }
            }
            continue
        }
        if (l.indexOf("default:") === 0) {
            if (!cur) continue
            var d = parseInt(l.substring(8).trim())
            if (!isNaN(d)) out.defaults[cur] = d
            continue
        }
        cur = l.replace(":", "").trim()
        out.supported[cur] = true
    }
    // Keep the legacy camelCase flags the panel's `visible:` bindings read.
    out.supported.panelOverdrive = !!out.supported["panel_overdrive"]
    out.supported.gpuMux         = !!out.supported["gpu_mux_mode"]
    out.supported.dgpuDisable    = !!out.supported["dgpu_disable"]
    out.supported.pptPl1         = !!out.supported["ppt_pl1_spl"]
    out.supported.pptPl2         = !!out.supported["ppt_pl2_sppt"]
    out.supported.nvDynBoost     = !!out.supported["nv_dynamic_boost"]
    out.supported.nvTempTarget   = !!out.supported["nv_temp_target"]
    return out
}

function parseArmouryValue(raw) {
    var text = String(raw || "").trim()
    // Range: "25..[115]..45" — checked first, since it also uses brackets.
    var rm = text.match(/(\d+)\.\.\[(\d+)\]\.\.(\d+)/)
    if (rm) return { type: "range", value: parseInt(rm[2]), min: parseInt(rm[1]), max: parseInt(rm[3]) }
    // Enum/toggle: "[(0),1]" or "[0,(1)]" — parentheses mark the *current*
    // option, and they can sit on any entry, so scan rather than assuming the
    // first one is selected (assuming that made every toggle read as "off").
    var tm = text.match(/^\[(.+)\]$/)
    if (tm) {
        var opts = tm[1].split(",").map(function(s) { return s.trim() })
        for (var i = 0; i < opts.length; i++) {
            var pm = opts[i].match(/^\((\d+)\)$/)
            if (pm) return { type: "toggle", value: parseInt(pm[1]) }
        }
    }
    return null
}

// ============================================================
// LED brightness
// ============================================================
function parseLedBrightness(raw) {
    var text = String(raw || "").trim().toLowerCase()
    if (text.indexOf("off") >= 0) return "off"
    if (text.indexOf("high") >= 0) return "high"
    if (text.indexOf("med") >= 0) return "med"
    if (text.indexOf("low") >= 0) return "low"
    return "off"
}

// ============================================================
// Color helpers
// ============================================================
function rgbToHex(r, g, b) {
    var rh = Math.max(0, Math.min(255, Math.round(r))).toString(16)
    var gh = Math.max(0, Math.min(255, Math.round(g))).toString(16)
    var bh = Math.max(0, Math.min(255, Math.round(b))).toString(16)
    if (rh.length < 2) rh = "0" + rh
    if (gh.length < 2) gh = "0" + gh
    if (bh.length < 2) bh = "0" + bh
    return rh + gh + bh
}

function hexToRgb(hex) {
    var h = String(hex).replace("#", "")
    if (h.length === 3) h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2]
    if (h.length !== 6) return { r: 255, g: 255, b: 255 }
    return { r: parseInt(h.substring(0, 2), 16) || 0, g: parseInt(h.substring(2, 4), 16) || 0, b: parseInt(h.substring(4, 6), 16) || 0 }
}

var presetColors = [
    { name: "Red",    hex: "ff0000" }, { name: "Orange", hex: "ff8800" },
    { name: "Yellow", hex: "ffff00" }, { name: "Green",  hex: "00ff00" },
    { name: "Cyan",   hex: "00ffff" }, { name: "Blue",   hex: "0088ff" },
    { name: "Purple", hex: "aa00ff" }, { name: "Pink",   hex: "ff00ff" },
    { name: "White",  hex: "ffffff" }, { name: "Warm",   hex: "ffaa44" },
    { name: "Ice",    hex: "44ccff" }, { name: "Lime",   hex: "88ff00" }
]

// ============================================================
// Live sensors
// ============================================================
// One shell round-trip per tick instead of a Process per reading. hwmon
// indices are not stable across boots, so chips are matched by their `name`
// file rather than a hardcoded hwmonN path. nvidia-smi is optional — the
// block is skipped entirely on machines without it, and the GPU tiles hide
// themselves when the keys never arrive.
var sensorScript =
    'for h in /sys/class/hwmon/*; do n=$(cat "$h/name" 2>/dev/null); case "$n" in ' +
    'coretemp|k10temp|zenpower) echo "cpu_temp=$(cat "$h/temp1_input" 2>/dev/null)";; ' +
    'asus) echo "fan_cpu=$(cat "$h/fan1_input" 2>/dev/null)"; echo "fan_gpu=$(cat "$h/fan2_input" 2>/dev/null)";; ' +
    'esac; done; ' +
    'b=/sys/class/power_supply/BAT0; if [ -d "$b" ]; then ' +
    'echo "bat_pct=$(cat $b/capacity 2>/dev/null)"; ' +
    'echo "bat_status=$(cat $b/status 2>/dev/null)"; ' +
    'echo "bat_power=$(cat $b/power_now 2>/dev/null)"; fi; ' +
    'if command -v nvidia-smi >/dev/null 2>&1; then ' +
    'nvidia-smi --query-gpu=temperature.gpu,power.draw,utilization.gpu --format=csv,noheader,nounits 2>/dev/null ' +
    '| head -1 | tr -d " " | { IFS=, read t p u; echo "gpu_temp=$t"; echo "gpu_power=$p"; echo "gpu_util=$u"; }; fi'

function sensorCommand() { return ["sh", "-c", sensorScript] }

// -1 means "not reported" throughout; callers hide the tile rather than
// printing a bogus zero.
function parseSensors(raw) {
    var r = { cpuTemp: -1, gpuTemp: -1, gpuPower: -1, gpuUtil: -1, fanCpu: -1, fanGpu: -1, batPct: -1, batStatus: "", batPower: -1 }
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
        var eq = lines[i].indexOf("=")
        if (eq < 0) continue
        var k = lines[i].substring(0, eq).trim(), v = lines[i].substring(eq + 1).trim()
        if (v === "") continue
        var n = parseFloat(v)
        if (k === "cpu_temp" && !isNaN(n)) r.cpuTemp = Math.round(n / 1000)
        else if (k === "gpu_temp" && !isNaN(n)) r.gpuTemp = Math.round(n)
        else if (k === "gpu_power" && !isNaN(n)) r.gpuPower = Math.round(n)
        else if (k === "gpu_util" && !isNaN(n)) r.gpuUtil = Math.round(n)
        else if (k === "fan_cpu" && !isNaN(n)) r.fanCpu = Math.round(n)
        else if (k === "fan_gpu" && !isNaN(n)) r.fanGpu = Math.round(n)
        else if (k === "bat_pct" && !isNaN(n)) r.batPct = Math.round(n)
        else if (k === "bat_power" && !isNaN(n)) r.batPower = n / 1000000
        else if (k === "bat_status") r.batStatus = v
    }
    return r
}

// Cool -> hot ramp shared by every temperature readout.
function tempColor(c) {
    if (c < 0) return "#888888"
    if (c >= 90) return "#ff4444"
    if (c >= 80) return "#ff8844"
    if (c >= 65) return "#ffcc44"
    return "#44cc66"
}

function fmtTemp(c) { return c < 0 ? "—" : c + "°C" }
function fmtRpm(r) { return r < 0 ? "—" : (r === 0 ? "off" : r + " rpm") }
function fmtWatts(w) { return w < 0 ? "—" : (Math.round(w * 10) / 10) + " W" }

// ============================================================
// GPU mode (G-Helper's Eco / Standard / Ultimate)
// ============================================================
// asusctl has no single "gpu mode" knob, so the three modes are expressed as
// the pair of armoury attributes G-Helper drives on Windows:
//   Eco      dGPU powered down, iGPU drives the panel
//   Standard hybrid / Optimus, dGPU available on demand
//   Ultimate MUX hands the panel straight to the dGPU (reboot required)
//
// gpu_mux_mode is NOT "1 means the MUX is engaged". Per the kernel ABI
// (Documentation/ABI/testing/sysfs-platform-asus-wmi) the value is:
//
//   0 - Discrete GPU     (the MUX routes the panel to the dGPU -> Ultimate)
//   1 - Optimus/Hybrid   (the iGPU drives the panel -> Eco / Standard)
//
// so it reads inverted next to every other toggle here, where 1 is the
// "more" setting. Taking it for a plain on/off flag put Ultimate and
// Standard the wrong way round: picking Standard rebooted the laptop into
// discrete mode, which also drops the iGPU's backlight device and leaves
// the brightness keys writing to a panel nothing is driving.
var gpuModes = [
    { id: "eco",      name: "Eco",      icon: "\u{F06C0}", desc: "iGPU only, dGPU off",  mux: 1, dgpuDisable: 1, reboot: false,
      tip: "Powers the discrete GPU down completely.\nBest battery life; games and CUDA will not see a dGPU." },
    { id: "standard", name: "Standard", icon: "\u{F035B}", desc: "Hybrid (Optimus)",     mux: 1, dgpuDisable: 0, reboot: false,
      tip: "Hybrid graphics. The iGPU drives the screen and the\ndiscrete GPU wakes on demand. The normal setting." },
    { id: "ultimate", name: "Ultimate", icon: "\u{F04C5}", desc: "dGPU direct — needs reboot", mux: 0, dgpuDisable: 0, reboot: true,
      tip: "MUX switch: the discrete GPU drives the internal panel\ndirectly. Fastest for games, costs battery life.\nTakes effect after a reboot." }
]

// Tooltip copy for the firmware attributes on the Advanced tab. Keyed by the
// asusctl armoury attribute name.
var armouryTips = {
    ppt_pl1_spl: "Sustained CPU power limit (PL1).\nThe wattage the CPU settles at under a long load.",
    ppt_pl2_sppt: "Short-burst CPU power limit (PL2).\nThe wattage the CPU may pull briefly before dropping to PL1.",
    nv_dynamic_boost: "NVIDIA Dynamic Boost.\nExtra watts the GPU may borrow from the CPU's budget when the CPU is idle.",
    nv_temp_target: "GPU temperature target.\nThe GPU throttles itself to stay at or below this. Lower is cooler and quieter, and slower.",
    panel_overdrive: "Speeds up pixel transitions to cut ghosting at high refresh rates.\nCan cause slight overshoot artefacts on some panels."
}

// `hasMux` separates "this laptop reports gpu_mux_mode = 0", which means
// discrete, from "this laptop has no MUX", where the attribute never appears
// and the mux argument is only the caller's default. They are the same 0
// once the polarity is read correctly, so without the flag every mux-less
// laptop would report itself permanently in Ultimate.
function gpuModeId(mux, dgpuDisabled, hasMux) {
    if (hasMux && !mux) return "ultimate"
    return dgpuDisabled ? "eco" : "standard"
}

function gpuModeDef(id) {
    for (var i = 0; i < gpuModes.length; i++) if (gpuModes[i].id === id) return gpuModes[i]
    return gpuModes[1]
}

// ============================================================
// Display (G-Helper's 60Hz / max-Hz screen toggle)
// ============================================================
// Picks the built-in panel (eDP-*) when present — the refresh toggle is a
// laptop-screen feature, and on a docked machine the focused monitor is
// usually the external one. Falls back to the focused monitor otherwise.
function parseMonitors(rawJson) {
    var list
    try { list = JSON.parse(String(rawJson || "[]")) } catch (e) { return null }
    if (!Array.isArray(list) || list.length === 0) return null
    var m = null
    for (var i = 0; i < list.length; i++) if (String(list[i].name || "").indexOf("eDP") === 0) { m = list[i]; break }
    if (!m) for (var j = 0; j < list.length; j++) if (list[j].focused) { m = list[j]; break }
    if (!m) m = list[0]

    // availableModes entries look like "1920x1080@144.00Hz"; keep only the
    // rates offered at the resolution currently in use, deduped and sorted.
    var res = m.width + "x" + m.height
    var rates = [], seen = {}
    var modes = Array.isArray(m.availableModes) ? m.availableModes : []
    for (var k = 0; k < modes.length; k++) {
        var parts = String(modes[k]).split("@")
        if (parts.length !== 2 || parts[0] !== res) continue
        var hz = Math.round(parseFloat(parts[1]))
        if (isNaN(hz) || seen[hz]) continue
        seen[hz] = true
        rates.push(hz)
    }
    rates.sort(function(a, b) { return a - b })
    return {
        name: m.name, width: m.width, height: m.height,
        x: m.x, y: m.y, scale: m.scale,
        rate: Math.round(m.refreshRate), rates: rates
    }
}

// hyprmoncfg (a third-party monitor-profile daemon, not part of Omarchy) takes
// ownership of monitor config where it is installed: its daemon re-applies the
// active saved profile a few seconds after any runtime change, so a plain
// hl.monitor call silently snaps back. Where it is running, the new mode has to
// be saved into that profile as well — see setRefreshRate in Panel.qml.
function parseHyprmoncfgStatus(raw) {
    var r = { managed: false, profile: "" }
    var d
    try { d = JSON.parse(String(raw || "{}")) } catch (e) { return r }
    r.managed = !!(d && d.daemon && d.daemon.running)
    if (d && d.active_profile && d.active_profile.name) r.profile = String(d.active_profile.name)
    // A running daemon with no active profile has nothing to save back into,
    // so treat that as unmanaged rather than issuing a `save ""`.
    if (r.profile === "") r.managed = false
    return r
}

// Hyprland 0.56 parses its config as Lua, and `hyprctl keyword monitor`
// against it fails outright with "keyword can't work with non-legacy parsers.
// Use eval." — so the mode change goes through the Lua monitor API instead,
// the same call omarchy-hyprland-monitor-scaling uses.
//
// Position and scale are repeated explicitly: hl.monitor replaces the whole
// rule, so omitting them would reset the monitor's placement and scaling while
// changing only the rate.
function monitorCommand(mon, hz) {
    return ["hyprctl", "eval",
            'hl.monitor({ output = "' + mon.name + '"' +
            ', mode = "' + mon.width + "x" + mon.height + "@" + hz + '"' +
            ', position = "' + mon.x + "x" + mon.y + '"' +
            ", scale = " + mon.scale + " })"]
}

// ============================================================
// Index helpers
// ============================================================
function clampIndex(i, l) { return l <= 0 ? 0 : Math.max(0, Math.min(l - 1, i)) }
function selectProfileIndex(i, d, p) { var v = Array.isArray(p) ? p : []; return v.length === 0 ? 0 : clampIndex(i + d, v.length) }
function clamp(v, mn, mx) { return Math.max(mn, Math.min(mx, v)) }
