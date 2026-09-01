import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
    id: root
    moduleName: "io.github.moneytosms.asus"
    ipcTarget: "io.github.moneytosms.asus"
    manageIpc: false

    // Hosts like the Plugin Drawer set this to their own bar button so a
    // hidden/collapsed widget's panel still opens under the right icon
    // instead of the (invisible, off-bar) button this plugin owns itself.
    property var anchorItem: null

    // Reusable draggable fan-curve editor. Shows a temp/speed line with
    // draggable points; commits the whole curve via onCommit(points) on
    // release, and offers a per-fan reset via onReset(). Points never leave
    // [30,100]c / [0,100]% and stay ordered by temp — see Model.moveFanPoint.
    component FanCurveEditor: Column {
        id: editor
        property var points: []
        property bool enabledState: false
        property color accent: "#44cc44"
        property color foreground: "white"
        property string fontFamily: "monospace"
        property bool interactive: true
        signal commit(var points)
        signal reset()

        width: parent ? parent.width : 0
        spacing: Style.space(4)

        Rectangle {
            width: parent.width
            height: Style.space(64)
            radius: Style.cornerRadius
            color: Qt.rgba(editor.foreground.r, editor.foreground.g, editor.foreground.b, 0.04)
            opacity: editor.interactive ? 1 : 0.4

            Canvas {
                id: canvas
                anchors.fill: parent
                anchors.margins: Style.space(6)
                renderStrategy: Canvas.Immediate

                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    if (editor.points.length < 2) return
                    var w = width, h = height
                    ctx.strokeStyle = Qt.rgba(editor.foreground.r, editor.foreground.g, editor.foreground.b, 0.6)
                    ctx.lineWidth = 2
                    ctx.beginPath()
                    for (var i = 0; i < editor.points.length; i++) {
                        var px = (editor.points[i].temp - 30) / 70 * w
                        var py = h - (editor.points[i].speed / 100) * h
                        if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py)
                    }
                    ctx.stroke()
                }

                Connections { target: editor; function onPointsChanged() { canvas.requestPaint() } }

                Repeater {
                    model: editor.points
                    Rectangle {
                        id: handle
                        required property var modelData
                        required property int index
                        width: Style.space(10); height: Style.space(10); radius: Style.space(5)
                        color: editor.enabledState ? editor.accent : Qt.rgba(editor.foreground.r, editor.foreground.g, editor.foreground.b, 0.4)
                        border.width: 1
                        border.color: Qt.rgba(0, 0, 0, 0.3)
                        x: (modelData.temp - 30) / 70 * canvas.width - width / 2
                        y: canvas.height - (modelData.speed / 100) * canvas.height - height / 2

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -Style.space(4)
                            enabled: editor.interactive
                            cursorShape: Qt.PointingHandCursor
                            drag.target: handle
                            drag.axis: Drag.XAndYAxis
                            drag.minimumX: -handle.width / 2
                            drag.maximumX: canvas.width - handle.width / 2
                            drag.minimumY: -handle.height / 2
                            drag.maximumY: canvas.height - handle.height / 2
                            onPositionChanged: {
                                if (!drag.active) return
                                var temp = (handle.x + handle.width / 2) / canvas.width * 70 + 30
                                var speed = (1 - (handle.y + handle.height / 2) / canvas.height) * 100
                                editor.points = Model.moveFanPoint(editor.points, index, temp, speed)
                            }
                            onReleased: editor.commit(editor.points)
                        }
                    }
                }
            }

            // Sits under the handles so it never eats a drag, and explains the
            // axes — the graph has no room for labelled ones.
            MouseArea {
                id: curveHelp
                anchors.fill: parent
                z: -1
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
            }
            PanelToolTip {
                visible: curveHelp.containsMouse
                text: "Fan curve: temperature (30–100 °C) left to right,\nfan speed (0–100%) bottom to top.\nDrag a point to change it."
            }

            Text {
                anchors.bottom: parent.bottom; anchors.right: parent.right; anchors.margins: Style.space(2)
                text: editor.points.length + " pts"
                color: Qt.darker(editor.foreground, 1.6)
                font.family: editor.fontFamily
                font.pixelSize: 8
            }
        }

        Row {
            width: parent.width
            Item { width: parent.width - resetBtn.width; height: 1 }
            Button {
                id: resetBtn
                text: "Reset"
                tooltipText: "Restore this profile's default fan curves."
                fontSize: Style.font.caption
                foreground: editor.foreground
                fontFamily: editor.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY
                bordered: true
                onClicked: editor.reset()
            }
        }
    }

    // Compact readout tile used by the sensor strip: a caption, a big value,
    // and an optional second line. Kept dumb so the strip can reflow it into
    // however many columns the panel width allows.
    component SensorTile: Rectangle {
        id: tile
        property string caption: ""
        property string value: ""
        property string sub: ""
        property color valueColor: "white"
        property color foreground: "white"
        property string fontFamily: "monospace"
        property string tip: ""

        height: Style.space(46)
        radius: Style.cornerRadius
        color: Qt.rgba(tile.foreground.r, tile.foreground.g, tile.foreground.b, 0.05)

        MouseArea { id: tileHelp; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
        PanelToolTip { visible: tile.tip !== "" && tileHelp.containsMouse; text: tile.tip }

        Column {
            anchors.centerIn: parent
            spacing: Style.space(1)
            Text {
                text: tile.caption
                color: Qt.darker(tile.foreground, 1.7)
                font.family: tile.fontFamily; font.pixelSize: Style.font.caption; font.bold: true
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                text: tile.value
                color: tile.valueColor
                font.family: tile.fontFamily; font.pixelSize: Style.font.subtitle; font.bold: true
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                visible: tile.sub !== ""
                text: tile.sub
                color: Qt.darker(tile.foreground, 1.5)
                font.family: tile.fontFamily; font.pixelSize: Style.font.caption
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    property string currentProfile: ""
    property bool profileLoaded: false
    property bool infoLoaded: false
    property var profiles: ["Quiet", "Balanced", "Performance"]
    property int profileIndex: 1
    property var acProfile: ({ ac: "", battery: "" })
    property var supported: ({ hasAura: false, hasFanCurve: false, hasBattery: false, hasProfile: false, auraModes: [] })
    property bool fanCurveEnabled: false
    property int batteryLimit: 100
    property bool asusctlAvailable: false
    property bool cursorActive: false

    // Live sensors — refreshed on a faster tick than the asusctl state, since
    // temps and fan speeds are the numbers you actually watch move.
    property var sensors: ({ cpuTemp: -1, gpuTemp: -1, gpuPower: -1, gpuUtil: -1, fanCpu: -1, fanGpu: -1, batPct: -1, batStatus: "", batPower: -1 })
    readonly property bool hasNvidia: sensors.gpuTemp >= 0

    // Display — the built-in panel's current/available refresh rates, read
    // from Hyprland rather than asusctl (which has no display controls).
    property var monitor: null

    // Whether hyprmoncfg is installed, and whether its daemon is actively
    // managing displays. When it is, a runtime mode change has to be saved
    // back into the active profile or the daemon reverts it seconds later.
    property bool hyprmoncfgAvailable: false
    property bool hyprmoncfgManaged: false
    property string hyprmoncfgProfile: ""

    // ---- Tabs -----------------------------------------------------------
    property string tabKey: "main"
    readonly property var tabs: {
        var t = [{ key: "main", label: "Main" }]
        if (root.supported.hasAura || !root.infoLoaded) t.push({ key: "rgb", label: "RGB" })
        if (root.supported.hasFanCurve || !root.infoLoaded) t.push({ key: "fan", label: "Fan" })
        t.push({ key: "advanced", label: "Advanced" })
        return t
    }
    readonly property int tabIndex: { for (var i = 0; i < tabs.length; i++) if (tabs[i].key === tabKey) return i; return 0 }
    function selectTab(index) {
        if (tabs.length === 0) return
        var n = tabs.length, i = ((index % n) + n) % n
        tabKey = tabs[i].key
    }

    // RGB
    property string currentEffect: "static"
    property int colorR: 255
    property int colorG: 0
    property int colorB: 0
    property int color2R: 0
    property int color2G: 0
    property int color2B: 255
    property string currentSpeed: "med"
    property string currentDirection: "left"
    property bool ledAwake: true
    property bool ledBoot: true
    property bool ledSleep: true
    property string ledBrightness: "med"
    readonly property string colorHex: Model.rgbToHex(colorR, colorG, colorB)
    readonly property string color2Hex: Model.rgbToHex(color2R, color2G, color2B)
    readonly property color liveColor: Qt.rgba(colorR / 255, colorG / 255, colorB / 255, 1)
    readonly property color liveColor2: Qt.rgba(color2R / 255, color2G / 255, color2B / 255, 1)

    readonly property var auraSupportedEffects: Model.supportedEffects(root.supported.auraModes)
    readonly property var effectDef: { for (var i = 0; i < Model.effects.length; i++) { if (Model.effects[i].id === currentEffect) return Model.effects[i] }; return Model.effects[0] }
    readonly property bool needsColor: effectDef.params.indexOf("color") >= 0
    readonly property bool needsColor2: effectDef.params.indexOf("color2") >= 0
    readonly property bool needsSpeed: effectDef.params.indexOf("speed") >= 0
    readonly property bool needsDirection: effectDef.params.indexOf("direction") >= 0

    // Fan curves
    property bool cpuFanEnabled: false
    property bool gpuFanEnabled: false
    property bool midFanEnabled: false
    property bool hasMidFan: false
    property var cpuFanPoints: []
    property var gpuFanPoints: []
    property var midFanPoints: []
    // Which profile's curves the Fan tab is editing. asusctl stores one curve
    // set per power profile, so — like G-Helper — the editor targets a chosen
    // profile rather than silently always writing the active one.
    property string fanEditProfile: ""
    readonly property string fanProfile: fanEditProfile || currentProfile || "Balanced"

    // Armoury — armourySupported gates each Advanced control per-model, since
    // `asusctl armoury list` only reports attributes the running laptop
    // actually exposes (no dGPU / no panel overdrive on some models).
    property var armourySupported: ({ panelOverdrive: false, gpuMux: false, dgpuDisable: false, pptPl1: false, pptPl2: false, nvDynBoost: false, nvTempTarget: false })
    property var armouryDefaults: ({})
    property bool panelOverdrive: false
    property bool gpuMux: false
    property bool dgpuDisable: false
    property var gpuCommandQueue: []
    property int pptPl1: 115
    property int pptPl1Min: 25
    property int pptPl1Max: 45
    property int pptPl2: 135
    property int pptPl2Min: 35
    property int pptPl2Max: 60
    property int nvDynBoost: 25
    property int nvDynBoostMin: 0
    property int nvDynBoostMax: 25
    property int nvTempTarget: 87
    property int nvTempTargetMin: 75
    property int nvTempTargetMax: 87

    // GPU mode is derived from the mux/dgpu pair rather than stored, so it
    // can never drift out of sync with what the firmware actually reports.
    readonly property string gpuMode: Model.gpuModeId(gpuMux, dgpuDisable, armourySupported.gpuMux)
    readonly property bool hasGpuMode: armourySupported.gpuMux || armourySupported.dgpuDisable
    readonly property bool gpuModeBusy: gpuActionProc.running || gpuCommandQueue.length > 0

    readonly property bool showBatteryLimit: setting("showBatteryLimit", true) === true
    readonly property int refreshInterval: Math.max(5, Math.min(60, Number(setting("refreshIntervalSec", 10)) || 10)) * 1000

    function refresh() {
        if (!asusctlAvailable) { checkAsusctl.running = true; return }
        if (!profileProc.running) profileProc.running = true
        if (!infoProc.running) infoProc.running = true
        if (supported.hasBattery && !batteryProc.running) batteryProc.running = true
        if (!ledProc.running) ledProc.running = true
        if (!armouryProc.running) armouryProc.running = true
        if (!monitorProc.running) monitorProc.running = true
        if (hyprmoncfgAvailable && !hyprmoncfgProc.running) hyprmoncfgProc.running = true
        if (supported.hasFanCurve) { if (!fanDetailProc.running) fanDetailProc.running = true }
    }

    function setProfile(p) { if (!p || actionProc.running) return; actionProc.command = ["asusctl", "profile", "set", p]; actionProc.running = true }
    function cycleProfile(d) { profileIndex = Model.selectProfileIndex(profileIndex, d, profiles); setProfile(profiles[profileIndex]) }

    function applyEffect() {
        if (!supported.hasAura) return
        var params = {}
        if (needsColor) params.color = colorHex
        if (needsColor2) params.color2 = color2Hex
        if (needsSpeed) params.speed = currentSpeed
        if (needsDirection) params.direction = currentDirection
        actionProc.command = Model.buildAuraCommand(currentEffect, params); actionProc.running = true
    }
    function selectEffect(id) { currentEffect = id; applyEffect() }
    function setPresetColor(hex) { var r = Model.hexToRgb(hex); colorR = r.r; colorG = r.g; colorB = r.b; applyEffect() }
    function setPresetColor2(hex) { var r = Model.hexToRgb(hex); color2R = r.r; color2G = r.g; color2B = r.b; applyEffect() }

    // power-tuf takes all three states in one call, so each toggle resends the
    // full triple — sending only the changed flag makes asusctl default the
    // omitted ones back to false.
    function applyLedPower() {
        actionProc.command = ["asusctl", "aura", "power-tuf",
                              "--awake", ledAwake ? "true" : "false", "--keyboard",
                              "--boot", ledBoot ? "true" : "false",
                              "--sleep", ledSleep ? "true" : "false"]
        actionProc.running = true
    }
    function setLedPower(on) { ledAwake = on; applyLedPower() }
    function setLedBoot(on) { ledBoot = on; applyLedPower() }
    function setLedSleep(on) { ledSleep = on; applyLedPower() }
    function setLedBrightness(level) { ledBrightness = level; actionProc.command = ["asusctl", "leds", "set", level]; actionProc.running = true }
    function setBatteryLimit(l) { if (!supported.hasBattery) return; var c = Math.max(20, Math.min(100, Math.round(l))); actionProc.command = ["asusctl", "battery", "limit", String(c)]; actionProc.running = true }

    // Fan curves — every write is gated on profileLoaded so an action never
    // silently lands on the wrong (hardcoded "Balanced") profile because the
    // real active profile hadn't loaded yet. This was the root cause of fan
    // controls appearing to "not work sometimes".
    function toggleFanCurves() { if (!supported.hasFanCurve || !profileLoaded) return; var n = !fanCurveEnabled; actionProc.command = ["asusctl", "fan-curve", "--mod-profile", fanProfile, "--enable-fan-curves", n ? "true" : "false"]; actionProc.running = true }
    function toggleCpuFan() { if (!profileLoaded) return; var n = !cpuFanEnabled; actionProc.command = ["asusctl", "fan-curve", "--mod-profile", fanProfile, "--enable-fan-curve", n ? "true" : "false", "--fan", "cpu"]; actionProc.running = true }
    function toggleGpuFan() { if (!profileLoaded) return; var n = !gpuFanEnabled; actionProc.command = ["asusctl", "fan-curve", "--mod-profile", fanProfile, "--enable-fan-curve", n ? "true" : "false", "--fan", "gpu"]; actionProc.running = true }
    function toggleMidFan() { if (!profileLoaded || !hasMidFan) return; var n = !midFanEnabled; actionProc.command = ["asusctl", "fan-curve", "--mod-profile", fanProfile, "--enable-fan-curve", n ? "true" : "false", "--fan", "mid"]; actionProc.running = true }
    function resetFanCurves() { if (!profileLoaded) return; actionProc.command = ["asusctl", "fan-curve", "--mod-profile", fanProfile, "--default"]; actionProc.running = true }
    function applyFanCurve(fan, points) {
        if (!profileLoaded || actionProc.running) return
        actionProc.command = ["asusctl", "fan-curve", "--mod-profile", fanProfile, "--fan", fan, "--data", Model.serializeFanPoints(points)]
        actionProc.running = true
    }
    function selectFanProfile(p) { if (!p || p === fanProfile) return; fanEditProfile = p; if (!fanModProc.running) fanModProc.running = true }

    function setArmouryAttr(a, v) { actionProc.command = ["asusctl", "armoury", "set", a, String(v)]; actionProc.running = true }
    function togglePanelOverdrive() { panelOverdrive = !panelOverdrive; setArmouryAttr("panel_overdrive", panelOverdrive ? 1 : 0) }
    function setPptPl1(v) { pptPl1 = Math.round(v); setArmouryAttr("ppt_pl1_spl", pptPl1) }
    function setPptPl2(v) { pptPl2 = Math.round(v); setArmouryAttr("ppt_pl2_sppt", pptPl2) }
    function setNvDynBoost(v) { nvDynBoost = Math.round(v); setArmouryAttr("nv_dynamic_boost", nvDynBoost) }
    function setNvTempTarget(v) { nvTempTarget = Math.round(v); setArmouryAttr("nv_temp_target", nvTempTarget) }
    // Firmware ships a sane default per attribute; `asusctl armoury list`
    // reports it, so "Defaults" is just replaying those values.
    function restorePowerDefaults() {
        var d = root.armouryDefaults
        if (d.ppt_pl1_spl !== undefined) setPptPl1(d.ppt_pl1_spl)
        if (d.ppt_pl2_sppt !== undefined) setPptPl2(d.ppt_pl2_sppt)
        if (d.nv_dynamic_boost !== undefined) setNvDynBoost(d.nv_dynamic_boost)
        if (d.nv_temp_target !== undefined) setNvTempTarget(d.nv_temp_target)
    }

    // GPU mode — asusd queues both GPU attributes for safe application during
    // shutdown. Queue every supported half of the pair in the same order as
    // rog-control-center so a later selection fully replaces an earlier one.
    function setGpuMode(id) {
        if (gpuModeBusy) return
        var def = Model.gpuModeDef(id)
        gpuCommandQueue = Model.gpuModeCommands(id, armourySupported.gpuMux, armourySupported.dgpuDisable)
        if (gpuCommandQueue.length === 0) return
        gpuMux = def.mux === 1
        dgpuDisable = def.dgpuDisable === 1
        runNextGpuCommand()
    }

    function runNextGpuCommand() {
        if (gpuActionProc.running || gpuCommandQueue.length === 0) return
        var remaining = gpuCommandQueue.slice()
        gpuActionProc.command = remaining.shift()
        gpuCommandQueue = remaining
        gpuActionProc.running = true
    }

    // Applying a refresh rate is two steps where hyprmoncfg is managing
    // displays: change it live, then persist it into the daemon's active
    // profile. Without that second step hyprmoncfgd re-applies its saved
    // profile a few seconds later and the change silently reverts. On a
    // machine without the daemon the first step alone is the whole job.
    function setRefreshRate(hz) {
        if (!monitor || displayProc.running || hyprmoncfgSaveProc.running) return
        displayProc.command = Model.monitorCommand(monitor, hz)
        displayProc.running = true
    }

    visible: asusctlAvailable
    implicitWidth: asusctlAvailable ? button.implicitWidth : 0
    implicitHeight: asusctlAvailable ? button.implicitHeight : 0

    BarIconButton {
        id: button; anchors.fill: parent; bar: root.bar
        text: Model.profileIcon(currentProfile); slotSize: Style.bar.iconSlot
        // Tooltip doubles as the at-a-glance sensor readout, so the common
        // "how hot is it right now" question needs no click at all.
        tooltipText: {
            var t = "ASUS — " + Model.profileLabel(root.currentProfile)
            if (root.sensors.cpuTemp >= 0) t += "\nCPU  " + Model.fmtTemp(root.sensors.cpuTemp) + "   " + Model.fmtRpm(root.sensors.fanCpu)
            if (root.sensors.gpuTemp >= 0) t += "\nGPU  " + Model.fmtTemp(root.sensors.gpuTemp) + "   " + Model.fmtRpm(root.sensors.fanGpu)
            return t
        }
        onPressed: function(b) { root.toggle() }
        // Scroll cycles profiles without opening the panel — the fastest path
        // to Silent/Turbo, and what `cycleProfile` was written for.
        onWheelMoved: function(delta) { root.cycleProfile(delta > 0 ? 1 : -1) }
    }

    KeyboardPanel {
        id: panel; anchorItem: root.anchorItem || button; owner: root; bar: root.bar
        open: root.opened && root.asusctlAvailable; focusTarget: keyCatcher
        // The Flickable inside is inset by `flickMargin` on every side, so the
        // panel has to be asked for that much extra in both axes — sizing it
        // to the raw content height clipped the final row of whichever tab was
        // showing (the last slider on Advanced, the overdrive toggle on Main).
        readonly property real flickMargin: Style.space(12)
        contentWidth: panel.fittedContentWidth(Style.space(360) + flickMargin * 2)
        contentHeight: panel.fittedContentHeight(scrollCol.implicitHeight + flickMargin * 2)

        Flickable {
            id: flick
            anchors.fill: parent
            anchors.margins: panel.flickMargin
            contentHeight: scrollCol.implicitHeight
            clip: true
            flickableDirection: Flickable.VerticalFlick

            Column {
                id: scrollCol
                width: parent.width
                spacing: Style.space(12)

                // TABS — no hero header; the bar icon + active tab already
                // identify the panel, so the title/profile line is dropped
                // to give tab content more room before it needs to scroll.
                Row {
                    id: tabRow
                    width: parent.width
                    spacing: Style.space(4)
                    readonly property real cellWidth: root.tabs.length > 0 ? (width - spacing * (root.tabs.length - 1)) / root.tabs.length : 0
                    Repeater {
                        model: root.tabs
                        Button {
                            required property var modelData
                            required property int index
                            width: tabRow.cellWidth
                            text: modelData.label
                            fontSize: Style.font.bodySmall
                            foreground: root.bar.foreground
                            fontFamily: root.bar.fontFamily
                            horizontalPadding: Style.spacing.controlPaddingX
                            verticalPadding: Style.spacing.controlPaddingY
                            bordered: true
                            active: root.tabIndex === index
                            onClicked: root.selectTab(index)
                        }
                    }
                }

                PanelSeparator { foreground: root.bar.foreground }

                // Tab bodies are plain always-built Columns toggled by `visible`
                // rather than Loader/Component — Quickshell's incubator can take
                // multiple frames to finish building a freshly-activated Loader's
                // Component, which showed up as tab content intermittently
                // rendering blank/short right after opening. Building everything
                // up front as part of the panel's normal synchronous construction
                // avoids that race entirely.

                // ============================================================ MAIN TAB
                Column { visible: root.tabKey === "main"; width: parent.width; spacing: Style.space(12)

                    // LIVE SENSORS — G-Helper's home screen leads with temps
                    // and fan speeds, so this sits above the controls. Tiles
                    // for hardware that reports nothing stay hidden rather
                    // than showing a dash forever.
                    Grid {
                        id: sensorGrid
                        width: parent.width
                        columns: 2
                        spacing: Style.space(6)
                        readonly property real cw: (width - spacing) / 2

                        SensorTile {
                            width: sensorGrid.cw
                            caption: "CPU"
                            tip: "Package temperature and the CPU fan's current speed.\nSustained load on this laptop settles around 80–95 °C."
                            value: Model.fmtTemp(root.sensors.cpuTemp)
                            sub: Model.fmtRpm(root.sensors.fanCpu)
                            valueColor: Model.tempColor(root.sensors.cpuTemp)
                            foreground: root.bar.foreground; fontFamily: root.bar.fontFamily
                        }
                        SensorTile {
                            visible: root.hasNvidia
                            width: sensorGrid.cw
                            caption: "GPU"
                            tip: "Discrete GPU temperature, its fan speed, and how busy it is.\nIdles near 0% when nothing is using the dGPU."
                            value: Model.fmtTemp(root.sensors.gpuTemp)
                            sub: Model.fmtRpm(root.sensors.fanGpu) + (root.sensors.gpuUtil >= 0 ? "   " + root.sensors.gpuUtil + "%" : "")
                            valueColor: Model.tempColor(root.sensors.gpuTemp)
                            foreground: root.bar.foreground; fontFamily: root.bar.fontFamily
                        }
                        SensorTile {
                            visible: root.sensors.batPct >= 0
                            width: sensorGrid.cw
                            caption: "BATTERY"
                            tip: "Charge level, whether it is charging, and the current\nflow in watts — draw when discharging, fill rate when charging."
                            value: root.sensors.batPct + "%"
                            sub: root.sensors.batStatus + (root.sensors.batPower > 0 ? "   " + Model.fmtWatts(root.sensors.batPower) : "")
                            valueColor: root.sensors.batPct <= 15 && root.sensors.batStatus !== "Charging" ? "#ff4444" : root.bar.foreground
                            foreground: root.bar.foreground; fontFamily: root.bar.fontFamily
                        }
                        SensorTile {
                            visible: root.hasNvidia && root.sensors.gpuPower >= 0
                            width: sensorGrid.cw
                            caption: "GPU POWER"
                            tip: "Watts the discrete GPU is currently drawing, and the\ndynamic boost ceiling set on the Advanced tab."
                            value: root.sensors.gpuPower + " W"
                            sub: "boost " + root.nvDynBoost + "W"
                            valueColor: root.bar.foreground
                            foreground: root.bar.foreground; fontFamily: root.bar.fontFamily
                        }
                    }

                    Column { width: parent.width; spacing: Style.space(8)
                        PanelSeparator { foreground: root.bar.foreground }
                        PanelSectionHeader { text: "PERFORMANCE MODE"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }
                        Row { id: pRow; width: parent.width; spacing: Style.space(4); readonly property real cw: root.profiles.length > 0 ? (width - spacing * (root.profiles.length - 1)) / root.profiles.length : 0
                            Repeater { model: root.profiles
                                Button { required property var modelData; required property int index; width: pRow.cw; iconText: Model.profileIcon(String(modelData)); iconSize: Style.font.title; text: String(modelData); tooltipText: Model.profileDescription(String(modelData)); fontSize: Style.font.bodySmall; foreground: root.currentProfile === modelData ? Model.profileColor(String(modelData)) : root.bar.foreground; fontFamily: root.bar.fontFamily; horizontalPadding: Style.spacing.controlPaddingX; verticalPadding: Style.spacing.controlPaddingY; bordered: true; active: root.currentProfile === modelData; hasCursor: root.cursorActive && root.profileIndex === index; onClicked: root.setProfile(modelData); onHovered: function(h) { if (h) { root.cursorActive = true; root.profileIndex = index } } }
                            }
                        }
                    }

                    // GPU MODE — Eco / Standard / Ultimate, mirroring G-Helper.
                    Column { visible: root.hasGpuMode; width: parent.width; spacing: Style.space(8)
                        PanelSeparator { foreground: root.bar.foreground }
                        PanelSectionHeader { text: "GPU MODE"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }
                        Row { id: gRow; width: parent.width; spacing: Style.space(4); readonly property real cw: (width - spacing * 2) / 3
                            Repeater { model: Model.gpuModes
                                Button {
                                    required property var modelData
                                    readonly property bool modeAvailable: Model.gpuModeAvailable(modelData.id, root.armourySupported.gpuMux, root.armourySupported.dgpuDisable)
                                    width: gRow.cw
                                    // Ultimate needs the mux; hiding it outright would
                                    // shuffle the row, so it is disabled instead.
                                    enabled: modeAvailable && !root.gpuModeBusy
                                    opacity: enabled ? 1 : 0.4
                                    iconText: modelData.icon; iconSize: Style.font.title
                                    text: modelData.name
                                    tooltipText: modeAvailable ? modelData.tip : modelData.tip + "\n\nNot available: " + (modelData.id === "eco" ? "this laptop cannot disable the dGPU." : "this laptop has no MUX switch.")
                                    fontSize: Style.font.bodySmall
                                    foreground: root.bar.foreground; fontFamily: root.bar.fontFamily
                                    horizontalPadding: Style.spacing.controlPaddingX
                                    verticalPadding: Style.spacing.controlPaddingY
                                    bordered: true
                                    active: root.gpuMode === modelData.id
                                    onClicked: root.setGpuMode(modelData.id)
                                }
                            }
                        }
                        Text { width: parent.width; text: Model.gpuModeDef(root.gpuMode).desc; wrapMode: Text.WordWrap; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
                    }

                    // SCREEN — refresh rate comes from Hyprland, overdrive from
                    // asusctl; G-Helper pairs them in one control for the same
                    // reason (high refresh without OD looks smeary).
                    Column { visible: root.monitor !== null && root.monitor.rates.length > 1; width: parent.width; spacing: Style.space(8)
                        PanelSeparator { foreground: root.bar.foreground }
                        PanelSectionHeader { text: "SCREEN — " + (root.monitor ? root.monitor.name : "") + (root.hyprmoncfgManaged ? "  ·  " + root.hyprmoncfgProfile : ""); foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }
                        Row { id: hzRow; width: parent.width; spacing: Style.space(4); readonly property int n: root.monitor ? root.monitor.rates.length : 1; readonly property real cw: (width - spacing * (n - 1)) / Math.max(1, n)
                            Repeater { model: root.monitor ? root.monitor.rates : []
                                Button { required property var modelData; width: hzRow.cw; text: modelData + " Hz"; tooltipText: "Run " + (root.monitor ? root.monitor.name : "the panel") + " at " + modelData + " Hz.\n" + (modelData >= 90 ? "Smoother motion, noticeably more battery drain." : "Lower power draw, longer battery life.") + (root.hyprmoncfgManaged ? "\n\nSaved into the hyprmoncfg profile \"" + root.hyprmoncfgProfile + "\", so it sticks." : "\n\nApplied until the Hyprland config is reloaded."); fontSize: Style.font.bodySmall; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; horizontalPadding: Style.spacing.controlPaddingX; verticalPadding: Style.spacing.controlPaddingY; bordered: true; active: root.monitor && root.monitor.rate === modelData; onClicked: root.setRefreshRate(modelData) }
                            }
                        }
                        Toggle {
                            id: odToggle
                            visible: root.armourySupported.panelOverdrive
                            width: parent.width
                            label: "Panel Overdrive"
                            description: "Faster pixel response at high refresh"
                            checked: root.panelOverdrive
                            foreground: root.bar.foreground; accent: Color.accent; fontFamily: root.bar.fontFamily
                            onClicked: root.togglePanelOverdrive()
                            // Toggle reports hover as a signal rather than a
                            // property, so the tooltip tracks it via a flag.
                            property bool tipHovered: false
                            onHovered: function(h) { odToggle.tipHovered = h }
                            PanelToolTip { visible: odToggle.tipHovered; text: Model.armouryTips.panel_overdrive }
                        }
                    }

                    Column { visible: root.supported.hasBattery && root.showBatteryLimit; width: parent.width; spacing: Style.space(8)
                        PanelSeparator { foreground: root.bar.foreground }
                        PanelSectionHeader { text: "BATTERY CHARGE LIMIT"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }
                        Row { width: parent.width; spacing: Style.space(4)
                            PanelSlider { width: parent.width - Style.space(44) - Style.space(4); bar: root.bar; minimum: 20; maximum: 100; step: 5; integer: true; value: root.batteryLimit; tickCount: 9; onReleased: function(v) { root.setBatteryLimit(Math.round(v)) } }
                            Text { text: root.batteryLimit + "%"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body; font.bold: true; width: Style.space(44); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                        }
                        Row { width: parent.width; spacing: Style.space(4)
                            Repeater { model: [20, 40, 60, 80, 100]
                                Button { required property var modelData; width: (parent.width - Style.space(4) * 4) / 5; text: modelData + "%"; tooltipText: modelData === 100 ? "Charge to full.\nConvenient, but hardest on long-term battery health." : "Stop charging at " + modelData + "%.\nLower limits slow battery wear; 60–80% suits a mostly plugged-in laptop."; fontSize: Style.font.caption; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; horizontalPadding: Style.spacing.controlPaddingX; verticalPadding: Style.spacing.controlPaddingY; bordered: true; active: root.batteryLimit === modelData; onClicked: root.setBatteryLimit(modelData) }
                            }
                        }
                    }
                }

                // ============================================================= RGB TAB
                Column { visible: root.tabKey === "rgb"; width: parent.width; spacing: Style.space(8)
                    // Header with LED toggle
                    Row { width: parent.width
                        Text { text: "KEYBOARD RGB"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.subtitle; font.bold: true; anchors.verticalCenter: parent.verticalCenter; width: parent.width - ledSw.width - Style.space(8) }
                        Row { id: ledSw; spacing: Style.space(4); anchors.verticalCenter: parent.verticalCenter
                            Rectangle { width: Style.space(14); height: Style.space(14); radius: Style.space(7); color: root.ledAwake ? "#44cc44" : "#cc4444"; anchors.verticalCenter: parent.verticalCenter
                                SequentialAnimation on opacity { running: root.ledAwake; loops: Animation.Infinite; NumberAnimation { from: 1; to: 0.5; duration: 800 } NumberAnimation { from: 0.5; to: 1; duration: 800 } }
                            }
                            Text { text: root.ledAwake ? "ON" : "OFF"; color: root.ledAwake ? "#44cc44" : "#cc4444"; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                            MouseArea { id: ledPowerMouse; width: Style.space(40); height: Style.space(20); anchors.verticalCenter: parent.verticalCenter; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.setLedPower(!root.ledAwake)
                                PanelToolTip { visible: ledPowerMouse.containsMouse; text: root.ledAwake ? "Keyboard lighting is on. Click to turn it off." : "Keyboard lighting is off. Click to turn it on." }
                            }
                        }
                    }
                    // Effect grid — only modes this laptop's asusctl actually reports supporting.
                    Grid { width: parent.width; columns: 3; spacing: Style.space(3)
                        Repeater { model: root.auraSupportedEffects
                            Rectangle { required property var modelData; width: (parent.width - Style.space(3) * 2) / 3; height: Style.space(40); radius: Style.cornerRadius; color: root.currentEffect === modelData.id ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.2) : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.06); border.width: root.currentEffect === modelData.id ? 2 : 1; border.color: root.currentEffect === modelData.id ? root.bar.foreground : "transparent"
                                Row { anchors.centerIn: parent; spacing: Style.space(4)
                                    Text { text: modelData.icon; color: root.currentEffect === modelData.id ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
                                    Text { text: modelData.name; color: root.currentEffect === modelData.id ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.6); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
                                }
                                MouseArea { id: fxMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.selectEffect(modelData.id) }
                                PanelToolTip { visible: fxMouse.containsMouse; text: modelData.tip }
                            }
                        }
                    }
                    // Effect params
                    Column { visible: root.needsColor || root.needsColor2 || root.needsSpeed || root.needsDirection; width: parent.width; spacing: Style.space(6)
                        Column { visible: root.needsColor; width: parent.width; spacing: Style.space(4)
                            Row { width: parent.width; spacing: Style.space(6)
                                Rectangle { width: Style.space(20); height: Style.space(20); radius: Style.space(10); color: root.liveColor; border.width: 1; border.color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.3); anchors.verticalCenter: parent.verticalCenter }
                                Text { text: "Color  #" + root.colorHex.toUpperCase(); color: root.bar.foreground; font.family: "monospace"; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
                                Item { width: parent.width - Style.space(20) - Style.space(60) - Style.space(6) * 2; height: 1 }
                                Button { text: "Set"; fontSize: Style.font.caption; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; horizontalPadding: Style.spacing.controlPaddingX; verticalPadding: Style.spacing.controlPaddingY; bordered: true; active: true; anchors.verticalCenter: parent.verticalCenter; onClicked: root.applyEffect() }
                            }
                            Row { width: parent.width; spacing: Style.space(4)
                                Text { text: "R"; color: "#ff4444"; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; width: Style.space(12); anchors.verticalCenter: parent.verticalCenter }
                                PanelSlider { width: parent.width - Style.space(12) - Style.space(24) - Style.space(4) * 2; bar: root.bar; minimum: 0; maximum: 255; step: 1; integer: true; value: root.colorR; fillColor: Qt.rgba(1, 0.2, 0.2, 1); knobColor: Qt.rgba(1, 0.3, 0.3, 1); onReleased: function(v) { root.colorR = Math.round(v) } }
                                Text { text: root.colorR; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; width: Style.space(24); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                            }
                            Row { width: parent.width; spacing: Style.space(4)
                                Text { text: "G"; color: "#44cc44"; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; width: Style.space(12); anchors.verticalCenter: parent.verticalCenter }
                                PanelSlider { width: parent.width - Style.space(12) - Style.space(24) - Style.space(4) * 2; bar: root.bar; minimum: 0; maximum: 255; step: 1; integer: true; value: root.colorG; fillColor: Qt.rgba(0.2, 1, 0.2, 1); knobColor: Qt.rgba(0.3, 1, 0.3, 1); onReleased: function(v) { root.colorG = Math.round(v) } }
                                Text { text: root.colorG; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; width: Style.space(24); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                            }
                            Row { width: parent.width; spacing: Style.space(4)
                                Text { text: "B"; color: "#4488ff"; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; width: Style.space(12); anchors.verticalCenter: parent.verticalCenter }
                                PanelSlider { width: parent.width - Style.space(12) - Style.space(24) - Style.space(4) * 2; bar: root.bar; minimum: 0; maximum: 255; step: 1; integer: true; value: root.colorB; fillColor: Qt.rgba(0.2, 0.2, 1, 1); knobColor: Qt.rgba(0.3, 0.3, 1, 1); onReleased: function(v) { root.colorB = Math.round(v) } }
                                Text { text: root.colorB; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; width: Style.space(24); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                            }
                        }
                        Column { visible: root.needsColor2; width: parent.width; spacing: Style.space(4)
                            Row { width: parent.width; spacing: Style.space(6)
                                Rectangle { width: Style.space(20); height: Style.space(20); radius: Style.space(10); color: root.liveColor2; border.width: 1; border.color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.3); anchors.verticalCenter: parent.verticalCenter }
                                Text { text: "Color 2  #" + root.color2Hex.toUpperCase(); color: root.bar.foreground; font.family: "monospace"; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
                            }
                            Row { width: parent.width; spacing: Style.space(4)
                                Text { text: "R"; color: "#ff4444"; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; width: Style.space(12); anchors.verticalCenter: parent.verticalCenter }
                                PanelSlider { width: parent.width - Style.space(12) - Style.space(24) - Style.space(4) * 2; bar: root.bar; minimum: 0; maximum: 255; step: 1; integer: true; value: root.color2R; fillColor: Qt.rgba(1, 0.2, 0.2, 1); knobColor: Qt.rgba(1, 0.3, 0.3, 1); onReleased: function(v) { root.color2R = Math.round(v) } }
                                Text { text: root.color2R; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; width: Style.space(24); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                            }
                            Row { width: parent.width; spacing: Style.space(4)
                                Text { text: "G"; color: "#44cc44"; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; width: Style.space(12); anchors.verticalCenter: parent.verticalCenter }
                                PanelSlider { width: parent.width - Style.space(12) - Style.space(24) - Style.space(4) * 2; bar: root.bar; minimum: 0; maximum: 255; step: 1; integer: true; value: root.color2G; fillColor: Qt.rgba(0.2, 1, 0.2, 1); knobColor: Qt.rgba(0.3, 1, 0.3, 1); onReleased: function(v) { root.color2G = Math.round(v) } }
                                Text { text: root.color2G; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; width: Style.space(24); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                            }
                            Row { width: parent.width; spacing: Style.space(4)
                                Text { text: "B"; color: "#4488ff"; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; width: Style.space(12); anchors.verticalCenter: parent.verticalCenter }
                                PanelSlider { width: parent.width - Style.space(12) - Style.space(24) - Style.space(4) * 2; bar: root.bar; minimum: 0; maximum: 255; step: 1; integer: true; value: root.color2B; fillColor: Qt.rgba(0.2, 0.2, 1, 1); knobColor: Qt.rgba(0.3, 0.3, 1, 1); onReleased: function(v) { root.color2B = Math.round(v) } }
                                Text { text: root.color2B; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; width: Style.space(24); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                            }
                        }
                        Row { visible: root.needsSpeed; width: parent.width; spacing: Style.space(4)
                            Text { text: "Speed"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter; width: Style.space(40) }
                            Repeater { model: Model.speeds
                                Button { required property var modelData; width: (parent.width - Style.space(40) - Style.space(4) * 2) / 3; text: Model.speedLabels[modelData]; tooltipText: "How fast the " + root.effectDef.name + " effect animates."; fontSize: Style.font.caption; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; horizontalPadding: Style.spacing.controlPaddingX; verticalPadding: Style.spacing.controlPaddingY; bordered: true; active: root.currentSpeed === modelData; onClicked: { root.currentSpeed = modelData; root.applyEffect() } }
                            }
                        }
                        Row { visible: root.needsDirection; width: parent.width; spacing: Style.space(4)
                            Text { text: "Dir"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter; width: Style.space(40) }
                            Repeater { model: Model.directions
                                Button { required property var modelData; width: (parent.width - Style.space(40) - Style.space(4) * 3) / 4; text: modelData.charAt(0).toUpperCase() + modelData.slice(1); tooltipText: "Animate the effect towards the " + modelData + "."; fontSize: Style.font.caption; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; horizontalPadding: Style.spacing.controlPaddingX; verticalPadding: Style.spacing.controlPaddingY; bordered: true; active: root.currentDirection === modelData; onClicked: { root.currentDirection = modelData; root.applyEffect() } }
                            }
                        }
                        Grid { visible: root.needsColor; width: parent.width; columns: 6; spacing: Style.space(3)
                            Repeater {
                                model: ["ff0000", "ff8800", "ffff00", "00ff00", "00ffff", "0088ff", "aa00ff", "ff00ff", "ffffff", "ffaa44", "44ccff", "88ff00"]
                                Rectangle {
                                    required property string modelData
                                    property color swatchColor: Qt.rgba(
                                        parseInt(modelData.substring(0, 2), 16) / 255,
                                        parseInt(modelData.substring(2, 4), 16) / 255,
                                        parseInt(modelData.substring(4, 6), 16) / 255,
                                        1
                                    )
                                    width: (parent.width - Style.space(3) * 5) / 6
                                    height: Style.space(22)
                                    radius: Style.space(4)
                                    color: swatchColor
                                    border.width: root.colorHex === modelData ? 2 : 1
                                    border.color: root.colorHex === modelData ? root.bar.foreground : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.15)
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setPresetColor(modelData) }
                                }
                            }
                        }
                    }
                    // LED Brightness
                    Column { width: parent.width; spacing: Style.space(4)
                        Text { text: "LED Brightness"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
                        Row { width: parent.width; spacing: Style.space(4)
                            Repeater { model: ["off", "low", "med", "high"]
                                Button { required property var modelData; width: (parent.width - Style.space(4) * 3) / 4; text: modelData.charAt(0).toUpperCase() + modelData.slice(1); tooltipText: modelData === "off" ? "Turn the keyboard backlight off entirely." : "Set keyboard backlight brightness to " + modelData + "."; fontSize: Style.font.caption; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; horizontalPadding: Style.spacing.controlPaddingX; verticalPadding: Style.spacing.controlPaddingY; bordered: true; active: root.ledBrightness === modelData; onClicked: root.setLedBrightness(modelData) }
                            }
                        }
                    }

                    // Power states — G-Helper's "keyboard lighting on
                    // boot/sleep/awake". asusctl exposes these as one call, so
                    // each toggle resends the whole set (see applyLedPower).
                    Column { width: parent.width; spacing: Style.space(4)
                        PanelSeparator { foreground: root.bar.foreground }
                        Text { text: "Lighting active while"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
                        Row { width: parent.width; spacing: Style.space(4)
                            Button { width: (parent.width - Style.space(4) * 2) / 3; text: "Awake"; tooltipText: "Keep the keyboard lit while the laptop is in normal use."; fontSize: Style.font.caption; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; horizontalPadding: Style.spacing.controlPaddingX; verticalPadding: Style.spacing.controlPaddingY; bordered: true; active: root.ledAwake; onClicked: root.setLedPower(!root.ledAwake) }
                            Button { width: (parent.width - Style.space(4) * 2) / 3; text: "Boot"; tooltipText: "Play the lighting animation during power-on and shutdown."; fontSize: Style.font.caption; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; horizontalPadding: Style.spacing.controlPaddingX; verticalPadding: Style.spacing.controlPaddingY; bordered: true; active: root.ledBoot; onClicked: root.setLedBoot(!root.ledBoot) }
                            Button { width: (parent.width - Style.space(4) * 2) / 3; text: "Sleep"; tooltipText: "Keep a breathing light going while the laptop is suspended."; fontSize: Style.font.caption; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; horizontalPadding: Style.spacing.controlPaddingX; verticalPadding: Style.spacing.controlPaddingY; bordered: true; active: root.ledSleep; onClicked: root.setLedSleep(!root.ledSleep) }
                        }
                        Text { width: parent.width; text: "asusctl does not report these back, so they show what this panel last set."; wrapMode: Text.WordWrap; color: Qt.darker(root.bar.foreground, 1.6); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
                    }
                }

                // ============================================================= FAN TAB
                Column { visible: root.tabKey === "fan"; width: parent.width; spacing: Style.space(10)

                    Row { width: parent.width
                        Text { text: "CUSTOM FAN CURVES"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.subtitle; font.bold: true; anchors.verticalCenter: parent.verticalCenter; width: parent.width - masterSw.width - resetAllBtn.width - Style.space(16) }
                        Rectangle { id: masterSw; width: Style.space(48); height: Style.space(20); radius: Style.space(10); anchors.verticalCenter: parent.verticalCenter; color: root.fanCurveEnabled ? Qt.rgba(0.27, 0.8, 0.27, 0.3) : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.08)
                            MouseArea { id: masterSwMouse; anchors.fill: parent; hoverEnabled: true; enabled: root.profileLoaded; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleFanCurves() }
                            PanelToolTip { visible: masterSwMouse.containsMouse; text: "Master switch for custom fan curves.\nOff means the firmware's own curves run instead." }
                            Text { text: root.fanCurveEnabled ? "ON" : "OFF"; color: root.fanCurveEnabled ? "#44cc44" : Qt.darker(root.bar.foreground, 1.6); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; anchors.centerIn: parent }
                        }
                        Button { id: resetAllBtn; text: "Reset all"; tooltipText: "Restore the firmware's default fan curves\nfor the profile selected below."; fontSize: Style.font.caption; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; horizontalPadding: Style.spacing.controlPaddingX; verticalPadding: Style.spacing.controlPaddingY; bordered: true; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: Style.space(6); onClicked: root.resetFanCurves() }
                    }
                    Text { visible: !root.fanCurveEnabled; width: parent.width; text: "Turn this on to enable per-fan custom curves below."; wrapMode: Text.WordWrap; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }

                    // Curves are stored per power profile. Editing whichever
                    // profile is active is rarely what you want when tuning,
                    // so the target is picked explicitly here.
                    Column { width: parent.width; spacing: Style.space(4)
                        Text { text: "Editing curves for"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
                        Row { id: fpRow; width: parent.width; spacing: Style.space(4); readonly property real cw: root.profiles.length > 0 ? (width - spacing * (root.profiles.length - 1)) / root.profiles.length : 0
                            Repeater { model: root.profiles
                                Button { required property var modelData; width: fpRow.cw; text: String(modelData) + (root.currentProfile === modelData ? " •" : ""); tooltipText: "Edit the fan curves stored for the " + modelData + " profile." + (root.currentProfile === modelData ? "\nThis is the profile currently active (•)." : "\nChanges apply when you switch to that profile."); fontSize: Style.font.caption; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; horizontalPadding: Style.spacing.controlPaddingX; verticalPadding: Style.spacing.controlPaddingY; bordered: true; active: root.fanProfile === modelData; onClicked: root.selectFanProfile(String(modelData)) }
                            }
                        }
                    }

                    // CPU Fan
                    Column { width: parent.width; spacing: Style.space(4); opacity: root.fanCurveEnabled ? 1 : 0.5
                        Row { width: parent.width; spacing: Style.space(8)
                            Rectangle { width: Style.space(12); height: Style.space(12); radius: Style.space(6); color: root.cpuFanEnabled ? "#44cc44" : "#666"; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: "CPU Fan"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: Model.fmtRpm(root.sensors.fanCpu) + "   " + Model.fmtTemp(root.sensors.cpuTemp); color: Qt.darker(root.bar.foreground, 1.5); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignRight; width: parent.width - Style.space(12) - Style.space(48) - Style.space(70) }
                            Rectangle { width: Style.space(48); height: Style.space(20); radius: Style.space(10); color: root.cpuFanEnabled ? Qt.rgba(0.27, 0.8, 0.27, 0.3) : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.08); anchors.verticalCenter: parent.verticalCenter
                                MouseArea { id: cpuSwMouse; anchors.fill: parent; hoverEnabled: true; enabled: root.fanCurveEnabled; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleCpuFan() }
                                PanelToolTip { visible: cpuSwMouse.containsMouse; text: "Use the custom curve below for the CPU fan." }
                                Text { text: root.cpuFanEnabled ? "ON" : "OFF"; color: root.cpuFanEnabled ? "#44cc44" : Qt.darker(root.bar.foreground, 1.6); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; anchors.centerIn: parent }
                            }
                        }
                        FanCurveEditor {
                            width: parent.width
                            points: root.cpuFanPoints
                            enabledState: root.cpuFanEnabled
                            interactive: root.fanCurveEnabled
                            accent: "#44cc44"
                            foreground: root.bar.foreground
                            fontFamily: root.bar.fontFamily
                            onCommit: function(pts) { root.cpuFanPoints = pts; root.applyFanCurve("cpu", pts) }
                            onReset: root.resetFanCurves()
                        }
                    }
                    // GPU Fan
                    Column { width: parent.width; spacing: Style.space(4); opacity: root.fanCurveEnabled ? 1 : 0.5
                        Row { width: parent.width; spacing: Style.space(8)
                            Rectangle { width: Style.space(12); height: Style.space(12); radius: Style.space(6); color: root.gpuFanEnabled ? "#4488ff" : "#666"; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: "GPU Fan"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: Model.fmtRpm(root.sensors.fanGpu) + (root.sensors.gpuTemp >= 0 ? "   " + Model.fmtTemp(root.sensors.gpuTemp) : ""); color: Qt.darker(root.bar.foreground, 1.5); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignRight; width: parent.width - Style.space(12) - Style.space(48) - Style.space(70) }
                            Rectangle { width: Style.space(48); height: Style.space(20); radius: Style.space(10); color: root.gpuFanEnabled ? Qt.rgba(0.27, 0.53, 1, 0.3) : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.08); anchors.verticalCenter: parent.verticalCenter
                                MouseArea { id: gpuSwMouse; anchors.fill: parent; hoverEnabled: true; enabled: root.fanCurveEnabled; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleGpuFan() }
                                PanelToolTip { visible: gpuSwMouse.containsMouse; text: "Use the custom curve below for the GPU fan." }
                                Text { text: root.gpuFanEnabled ? "ON" : "OFF"; color: root.gpuFanEnabled ? "#4488ff" : Qt.darker(root.bar.foreground, 1.6); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; anchors.centerIn: parent }
                            }
                        }
                        FanCurveEditor {
                            width: parent.width
                            points: root.gpuFanPoints
                            enabledState: root.gpuFanEnabled
                            interactive: root.fanCurveEnabled
                            accent: "#4488ff"
                            foreground: root.bar.foreground
                            fontFamily: root.bar.fontFamily
                            onCommit: function(pts) { root.gpuFanPoints = pts; root.applyFanCurve("gpu", pts) }
                            onReset: root.resetFanCurves()
                        }
                    }
                    // Mid Fan — only laptops with a third fan report this.
                    Column { visible: root.hasMidFan; width: parent.width; spacing: Style.space(4); opacity: root.fanCurveEnabled ? 1 : 0.5
                        Row { width: parent.width; spacing: Style.space(8)
                            Rectangle { width: Style.space(12); height: Style.space(12); radius: Style.space(6); color: root.midFanEnabled ? "#cc9944" : "#666"; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: "Mid Fan"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true; anchors.verticalCenter: parent.verticalCenter; width: parent.width - Style.space(60) }
                            Rectangle { width: Style.space(48); height: Style.space(20); radius: Style.space(10); color: root.midFanEnabled ? Qt.rgba(0.8, 0.6, 0.27, 0.3) : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.08); anchors.verticalCenter: parent.verticalCenter
                                MouseArea { id: midSwMouse; anchors.fill: parent; hoverEnabled: true; enabled: root.fanCurveEnabled; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleMidFan() }
                                PanelToolTip { visible: midSwMouse.containsMouse; text: "Use the custom curve below for the middle fan." }
                                Text { text: root.midFanEnabled ? "ON" : "OFF"; color: root.midFanEnabled ? "#cc9944" : Qt.darker(root.bar.foreground, 1.6); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; anchors.centerIn: parent }
                            }
                        }
                        FanCurveEditor {
                            width: parent.width
                            points: root.midFanPoints
                            enabledState: root.midFanEnabled
                            interactive: root.fanCurveEnabled
                            accent: "#cc9944"
                            foreground: root.bar.foreground
                            fontFamily: root.bar.fontFamily
                            onCommit: function(pts) { root.midFanPoints = pts; root.applyFanCurve("mid", pts) }
                            onReset: root.resetFanCurves()
                        }
                    }
                }

                // ======================================================== ADVANCED TAB
                Column { visible: root.tabKey === "advanced"; width: parent.width; spacing: Style.space(8)
                    Row { width: parent.width
                        Text { width: parent.width - defaultsBtn.width - Style.space(8); text: "Firmware power limits. Only the controls this laptop actually reports are shown."; wrapMode: Text.WordWrap; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
                        Button { id: defaultsBtn; text: "Defaults"; tooltipText: "Put every power limit below back to the value\nthe firmware reports as its default."; fontSize: Style.font.caption; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; horizontalPadding: Style.spacing.controlPaddingX; verticalPadding: Style.spacing.controlPaddingY; bordered: true; anchors.verticalCenter: parent.verticalCenter; onClicked: root.restorePowerDefaults() }
                    }
                    Column { visible: root.armourySupported.pptPl1 || root.armourySupported.pptPl2; width: parent.width; spacing: Style.space(4)
                        Text { text: "CPU Power"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
                        Row { visible: root.armourySupported.pptPl1; width: parent.width; spacing: Style.space(4)
                            Text { text: "PL1"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; width: Style.space(40); anchors.verticalCenter: parent.verticalCenter
                                MouseArea { id: pl1Help; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                                PanelToolTip { visible: pl1Help.containsMouse; text: Model.armouryTips.ppt_pl1_spl }
                            }
                            PanelSlider { width: parent.width - Style.space(40) - Style.space(32) - Style.space(4) * 2; bar: root.bar; minimum: root.pptPl1Min; maximum: root.pptPl1Max; step: 1; integer: true; value: root.pptPl1; onReleased: function(v) { root.setPptPl1(v) } }
                            Text { text: root.pptPl1 + "W"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; width: Style.space(32); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                        }
                        Row { visible: root.armourySupported.pptPl2; width: parent.width; spacing: Style.space(4)
                            Text { text: "PL2"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; width: Style.space(40); anchors.verticalCenter: parent.verticalCenter
                                MouseArea { id: pl2Help; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                                PanelToolTip { visible: pl2Help.containsMouse; text: Model.armouryTips.ppt_pl2_sppt }
                            }
                            PanelSlider { width: parent.width - Style.space(40) - Style.space(32) - Style.space(4) * 2; bar: root.bar; minimum: root.pptPl2Min; maximum: root.pptPl2Max; step: 1; integer: true; value: root.pptPl2; onReleased: function(v) { root.setPptPl2(v) } }
                            Text { text: root.pptPl2 + "W"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; width: Style.space(32); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                        }
                    }
                    Column { visible: root.armourySupported.nvDynBoost || root.armourySupported.nvTempTarget; width: parent.width; spacing: Style.space(4)
                        Text { text: "GPU Power"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
                        Row { visible: root.armourySupported.nvDynBoost; width: parent.width; spacing: Style.space(4)
                            Text { text: "Boost"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; width: Style.space(40); anchors.verticalCenter: parent.verticalCenter
                                MouseArea { id: boostHelp; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                                PanelToolTip { visible: boostHelp.containsMouse; text: Model.armouryTips.nv_dynamic_boost }
                            }
                            PanelSlider { width: parent.width - Style.space(40) - Style.space(32) - Style.space(4) * 2; bar: root.bar; minimum: root.nvDynBoostMin; maximum: root.nvDynBoostMax; step: 1; integer: true; value: root.nvDynBoost; onReleased: function(v) { root.setNvDynBoost(v) } }
                            Text { text: root.nvDynBoost + "W"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; width: Style.space(32); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                        }
                        Row { visible: root.armourySupported.nvTempTarget; width: parent.width; spacing: Style.space(4)
                            Text { text: "Temp"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; width: Style.space(40); anchors.verticalCenter: parent.verticalCenter
                                MouseArea { id: tempHelp; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                                PanelToolTip { visible: tempHelp.containsMouse; text: Model.armouryTips.nv_temp_target }
                            }
                            PanelSlider { width: parent.width - Style.space(40) - Style.space(32) - Style.space(4) * 2; bar: root.bar; minimum: root.nvTempTargetMin; maximum: root.nvTempTargetMax; step: 1; integer: true; value: root.nvTempTarget; onReleased: function(v) { root.setNvTempTarget(v) } }
                            Text { text: root.nvTempTarget + "°C"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; width: Style.space(32); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                        }
                    }
                }
            }
        }

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            onCloseRequested: root.close()
            onMoveRequested: function(dx, dy) { if (dy !== 0) flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY - dy * 40)) }
        }
    }

    IpcHandler { target: "io.github.moneytosms.asus"; function open() { root.open() } function close() { root.close() } function show() { root.open() } function hide() { root.close() } function toggle() { root.toggle() } function refresh() { root.refresh() } }
    onOpenedChanged: { if (opened) { Qt.callLater(refresh); cursorActive = false } }
    Component.onCompleted: { checkAsusctl.running = true; checkHyprmoncfg.running = true }

    Process { id: checkAsusctl; command: ["which", "asusctl"]; onExited: function(ec) { root.asusctlAvailable = ec === 0; if (root.asusctlAvailable) refresh() } }
    Process { id: profileProc; command: ["asusctl", "profile", "get"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: { var p = Model.parseCurrentProfile(text); if (p) { root.currentProfile = p; var i = root.profiles.indexOf(p); if (i >= 0) root.profileIndex = i }; root.acProfile = Model.parseProfiles(text); root.profileLoaded = true } } }
    Process { id: infoProc; command: ["asusctl", "info", "--show-supported"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: { root.supported = Model.parseSupportedFeatures(text); root.infoLoaded = true } } }
    Process { id: batteryProc; command: ["asusctl", "battery", "info"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: { root.batteryLimit = Model.parseBatteryInfo(text).limit } } }
    Process { id: ledProc; command: ["asusctl", "leds", "get"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: { root.ledBrightness = Model.parseLedBrightness(text) } } }
    Process {
        id: fanDetailProc
        command: ["asusctl", "fan-curve", "--get-enabled"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var info = Model.parseFanCurves(text)
                root.cpuFanEnabled = info.cpuEnabled
                root.gpuFanEnabled = info.gpuEnabled
                root.hasMidFan = info.hasMid
                root.midFanEnabled = info.midEnabled
                root.cpuFanPoints = info.cpuPoints
                root.gpuFanPoints = info.gpuPoints
                root.midFanPoints = info.midPoints
                root.fanCurveEnabled = info.cpuEnabled || info.gpuEnabled || (info.hasMid && info.midEnabled)
                // Also fetch detailed curve data
                if (!fanModProc.running) fanModProc.running = true
            }
        }
    }
    Process {
        id: fanModProc
        command: ["asusctl", "fan-curve", "--mod-profile", root.fanProfile]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var info = Model.parseFanCurves(text)
                if (info.cpuPoints.length > 0) root.cpuFanPoints = info.cpuPoints
                if (info.gpuPoints.length > 0) root.gpuFanPoints = info.gpuPoints
                if (info.midPoints.length > 0) { root.midFanPoints = info.midPoints; root.hasMidFan = true }
            }
        }
    }
    Process { id: armouryProc; command: ["asusctl", "armoury", "list"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
        var a = Model.parseArmoury(text)
        root.armourySupported = a.supported
        root.armouryDefaults = a.defaults
        var v = a.values, r = a.ranges
        if (v.panel_overdrive !== undefined) root.panelOverdrive = v.panel_overdrive === 1
        if (v.gpu_mux_mode !== undefined) root.gpuMux = v.gpu_mux_mode === 1
        if (v.dgpu_disable !== undefined) root.dgpuDisable = v.dgpu_disable === 1
        if (v.ppt_pl1_spl !== undefined) root.pptPl1 = v.ppt_pl1_spl
        if (r.ppt_pl1_spl) { root.pptPl1Min = r.ppt_pl1_spl.min; root.pptPl1Max = r.ppt_pl1_spl.max }
        if (v.ppt_pl2_sppt !== undefined) root.pptPl2 = v.ppt_pl2_sppt
        if (r.ppt_pl2_sppt) { root.pptPl2Min = r.ppt_pl2_sppt.min; root.pptPl2Max = r.ppt_pl2_sppt.max }
        if (v.nv_dynamic_boost !== undefined) root.nvDynBoost = v.nv_dynamic_boost
        if (r.nv_dynamic_boost) { root.nvDynBoostMin = r.nv_dynamic_boost.min; root.nvDynBoostMax = r.nv_dynamic_boost.max }
        if (v.nv_temp_target !== undefined) root.nvTempTarget = v.nv_temp_target
        if (r.nv_temp_target) { root.nvTempTargetMin = r.nv_temp_target.min; root.nvTempTargetMax = r.nv_temp_target.max }
    } } }
    Process { id: monitorProc; command: ["hyprctl", "-j", "monitors"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: { var m = Model.parseMonitors(text); if (m) root.monitor = m } } }
    Process { id: checkHyprmoncfg; command: ["which", "hyprmoncfg"]; onExited: function(ec) { root.hyprmoncfgAvailable = ec === 0; if (root.hyprmoncfgAvailable && !hyprmoncfgProc.running) hyprmoncfgProc.running = true } }
    // Re-read on every refresh: the active profile changes when monitors are
    // plugged or unplugged, and saving into a stale profile name would either
    // fail or overwrite the wrong one.
    Process { id: hyprmoncfgProc; command: ["hyprmoncfg", "status", "--json"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
        var s = Model.parseHyprmoncfgStatus(text)
        root.hyprmoncfgManaged = s.managed
        root.hyprmoncfgProfile = s.profile
    } } }
    Process {
        id: displayProc
        onExited: function(ec) {
            if (ec === 0 && root.hyprmoncfgManaged && root.hyprmoncfgProfile !== "" && !hyprmoncfgSaveProc.running) {
                hyprmoncfgSaveProc.command = ["hyprmoncfg", "save", root.hyprmoncfgProfile]
                hyprmoncfgSaveProc.running = true
                return
            }
            if (!monitorProc.running) monitorProc.running = true
        }
    }
    Process { id: hyprmoncfgSaveProc; onExited: function() { if (!monitorProc.running) monitorProc.running = true } }
    Process { id: sensorProc; command: Model.sensorCommand(); stdout: StdioCollector { waitForEnd: true; onStreamFinished: { root.sensors = Model.parseSensors(text) } } }
    Process { id: actionProc; onExited: function() { if (!profileProc.running) profileProc.running = true; if (!batteryProc.running) batteryProc.running = true; if (!ledProc.running) ledProc.running = true; if (!armouryProc.running) armouryProc.running = true; if (!monitorProc.running) monitorProc.running = true; if (!fanDetailProc.running) fanDetailProc.running = true } }
    Process { id: gpuActionProc; onExited: function() { root.runNextGpuCommand() } }
    Timer { interval: root.refreshInterval; running: root.opened && root.asusctlAvailable; repeat: true; onTriggered: root.refresh() }

    // Sensors run on their own, faster tick — the asusctl round-trip is much
    // heavier and its values barely move. Backs off while the panel is closed,
    // where the readings only feed the bar tooltip.
    Timer {
        interval: root.opened ? 2000 : 20000
        running: root.asusctlAvailable
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!sensorProc.running) sensorProc.running = true
    }
}
