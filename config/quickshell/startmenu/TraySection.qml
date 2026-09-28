import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import Quickshell.Services.Pipewire
import Quickshell.Widgets

Rectangle {
    id: root
    radius: 8
    color: "#000000"
    border.color: "#555753"
    border.width: 1

    property var menuWindow
    signal trayMenuRequested()

    readonly property string runtimeDir:
        Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string statsPath: runtimeDir + "/qs-startmenu-stats.json"

    property string clockText: "--:--"
    property string dateText: ""
    readonly property int clockPixelSize: 22
    implicitHeight: Math.max(176, trayCol.implicitHeight + 16)
    property string netText: "net --"
    property string cpuText: "cpu --"
    property string memText: "mem --"
    property string gpuText: "gpu --"
    property string tempText: "temp --"

    function refreshClock() {
        const now = new Date()
        clockText = Qt.formatDateTime(now, "HH:mm:ss")
        dateText = Qt.formatDateTime(now, "yyyy-MM-dd")
    }

    function refreshStats() {
        statsProc.running = false
        statsProc.running = true
    }

    function applyStats(raw) {
        try {
            const s = JSON.parse(raw)
            if (s.net)  netText  = s.net
            if (s.cpu)  cpuText  = s.cpu
            if (s.mem)  memText  = s.mem
            if (s.gpu)  gpuText  = s.gpu
            if (s.temp) tempText = s.temp
        } catch (e) {
            console.log("stats parse:", e)
        }
    }

    function showItemMenu(item, mouseArea, mouse) {
        if (!item || !root.menuWindow) return
        const p = mouseArea.mapToItem(null, mouse.x, mouse.y)
        root.trayMenuRequested()
        item.display(root.menuWindow, Math.round(p.x), Math.round(p.y))
    }

    Component.onCompleted: {
        refreshClock()
        refreshStats()
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.refreshClock()
    }

    Process {
        id: statsProc
        command: [
            "sh", "-c",
            "out='" + root.statsPath + "'; " +
            "iface=$(ip route show default 2>/dev/null | awk '{print $5; exit}'); " +
            "net='eth --'; " +
            "if [ -n \"$iface\" ]; then " +
            "  state=$(cat /sys/class/net/$iface/operstate 2>/dev/null || echo ?); " +
            "  if iwgetid -r >/dev/null 2>&1; then " +
            "    ssid=$(iwgetid -r 2>/dev/null || echo wifi); " +
            "    net=\"eth $ssid\"; " +
            "  else " +
            "    net=\"eth $iface $state\"; " +
            "  fi; " +
            "fi; " +
            "read c u n s i _ < /proc/stat; t1=$((u+n+s+i)); i1=$i; " +
            "sleep 0.12; " +
            "read c u n s i _ < /proc/stat; t2=$((u+n+s+i)); i2=$i; " +
            "dt=$((t2-t1)); di=$((i2-i1)); " +
            "if [ \"$dt\" -gt 0 ]; then cpu=$(( (100*(dt-di))/dt )); else cpu=0; fi; " +
            "cpu=\"cpu ${cpu}%\"; " +
            "mem_total=$(awk '/MemTotal/ {print $2}' /proc/meminfo); " +
            "mem_avail=$(awk '/MemAvailable/ {print $2}' /proc/meminfo); " +
            "mem_used=$(( (mem_total-mem_avail)/1024/1024 )); " +
            "mem_tot_g=$(awk -v t=$mem_total 'BEGIN{printf \"%.1f\", t/1024/1024}'); " +
            "mem=\"mem ${mem_used}/${mem_tot_g}G\"; " +
            "gpu='gpu --'; " +
            "if command -v nvidia-smi >/dev/null 2>&1; then " +
            "  g=$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' '); " +
            "  if [ -n \"$g\" ]; then " +
            "    gu=$(echo \"$g\" | cut -d, -f1); gt=$(echo \"$g\" | cut -d, -f2); " +
            "    gpu=\"gpu ${gu}% ${gt}°\"; " +
            "  fi; " +
            "elif [ -f /sys/class/drm/card0/device/gpu_busy_percent ]; then " +
            "  gu=$(cat /sys/class/drm/card0/device/gpu_busy_percent 2>/dev/null); " +
            "  gpu=\"gpu ${gu}%\"; " +
            "fi; " +
            "printf '{\"net\":\"%s\",\"cpu\":\"%s\",\"mem\":\"%s\",\"gpu\":\"%s\",\"temp\":\"%s\"}\\n' " +
            "  \"$net\" \"$cpu\" \"$mem\" \"$gpu\" > \"$out\""
        ]
        running: false
        onExited: {
            statsFile.path = root.statsPath
            statsFile.reload()
        }
    }

    FileView {
        id: statsFile
        onLoaded: root.applyStats(statsFile.text())
    }

    ColumnLayout {
        id: trayCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 8
        spacing: 6

        Row {
            Layout.fillWidth: true
            spacing: 4
            height: 28

            Repeater {
                model: SystemTray.items

                delegate: Item {
                    id: trayItem
                    required property var modelData
                    width: 28
                    height: 28

                    IconImage {
                        anchors.centerIn: parent
                        implicitSize: 20
                        source: modelData.icon
                    }

                    Rectangle {
                        visible: trayMouse.containsMouse
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.top
                        anchors.bottomMargin: 4
                        color: "#000000"
                        border.color: "#555753"
                        border.width: 1
                        radius: 4
                        width: tipText.implicitWidth + 10
                        height: tipText.implicitHeight + 6
                        z: 100

                        Text {
                            id: tipText
                            anchors.centerIn: parent
                            text: modelData.tooltipTitle
                                  || modelData.title
                                  || modelData.id
                                  || ""
                            color: "#EEEEEC"
                            font.pixelSize: 11
                        }
                    }

                    MouseArea {
                        id: trayMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        cursorShape: Qt.PointingHandCursor

                        onClicked: mouse => {
                            if (mouse.button === Qt.LeftButton) {
                                if (modelData.onlyMenu) {
                                    root.showItemMenu(modelData, trayMouse, mouse)
                                } else {
                                    modelData.activate()
                                }
                            } else if (mouse.button === Qt.MiddleButton) {
                                modelData.secondaryActivate()
                            } else if (mouse.button === Qt.RightButton) {
                                root.showItemMenu(modelData, trayMouse, mouse)
                            }
                        }

                        onWheel: wheel => modelData.scroll(wheel.angleDelta.y, false)
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            readonly property var sinkAudio: Pipewire.defaultAudioSink?.audio ?? null
            readonly property real volStep: 0.025
            readonly property real volMax: 1.5
            readonly property real vol: {
                const a = sinkAudio
                if (!a) return 0
                const v = a.volume
                return (typeof v === "number" && isFinite(v)) ? Math.max(0, v) : 0
            }
            readonly property bool muted: sinkAudio ? !!sinkAudio.muted : true
            readonly property bool over: vol > 1
            readonly property real volFill: {
                if (muted) return 0
                return Math.max(0, Math.min(1, vol / volMax))
            }

            function snapVolume(v) {
                const step = volStep
                if (typeof v !== "number" || !isFinite(v))
                    return 0
                return Math.max(0, Math.min(volMax, Math.round(v / step) * step))
            }

            function setVolumeFromRatio(ratio) {
                const a = sinkAudio
                if (!a) return
                const clamped = Math.max(0, Math.min(1, ratio))
                a.volume = snapVolume(clamped * volMax)
                a.muted = false
            }

            function nudgeVolume(dir) {
                const a = sinkAudio
                if (!a) return
                const current = (typeof a.volume === "number" && isFinite(a.volume)) ? a.volume : 0
                a.volume = snapVolume(current + (dir * volStep))
                a.muted = false
            }

            Text {
                text: {
                    if (!parent.sinkAudio || parent.muted || parent.vol === 0) return "MUTE"
                    return "VOL"
                }
                color: parent.over ? "#EF2929" : "#EEEEEC"
                font.pixelSize: 11
                font.family: "sans-serif"
                Layout.preferredWidth: 36

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (parent.parent.sinkAudio)
                            parent.parent.sinkAudio.muted = !parent.parent.sinkAudio.muted
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 8
                radius: 4
                color: "#555753"
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * parent.parent.volFill
                    radius: parent.radius
                    color: parent.parent.over ? "#EF2929" : "#729FCF"
                }
                Rectangle {
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    x: parent.width / parent.parent.volMax
                    width: 1
                    color: "#888A85"
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked: mouse => parent.parent.setVolumeFromRatio(mouse.x / width)
                    onPositionChanged: mouse => {
                        if (!pressed) return
                        parent.parent.setVolumeFromRatio(mouse.x / width)
                    }
                    onWheel: wheel => {
                        const delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.pixelDelta.y
                        if (delta === 0)
                            return
                        parent.parent.nudgeVolume(delta > 0 ? 1 : -1)
                        wheel.accepted = true
                    }
                }
            }

            Text {
                text: !parent.sinkAudio ? "--%"
                      : (Math.round((parent.muted ? 0 : parent.vol) * 1000) / 10) + "%"
                color: parent.over ? "#EF2929" : "#D3D7CF"
                font.pixelSize: 11
                Layout.preferredWidth: 48
                horizontalAlignment: Text.AlignRight
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: "#555753"
        }

        Flow {
            Layout.fillWidth: true
            spacing: 12

            Text {
                text: root.cpuText
                color: "#EEEEEC"
                font.pixelSize: 14
            }
            Text {
                text: root.memText
                color: "#EEEEEC"
                font.pixelSize: 14
            }
            Text {
                text: root.gpuText
                color: "#EEEEEC"
                font.pixelSize: 14
            }
            Text {
                text: root.netText
                color: "#EEEEEC"
                font.pixelSize: 14
            }
        }

        Column {
            Layout.fillWidth: true
            spacing: 0

            Text {
                text: root.clockText
                color: "#729FCF"
                font.pixelSize: root.clockPixelSize
                font.bold: true
            }
            Text {
                text: root.dateText
                color: "#729FCF"
                font.pixelSize: root.clockPixelSize
                font.bold: true
            }
        }
    }
}
