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
    color: "#181825"
    border.color: "#313244"
    border.width: 1

    property var menuWindow

    readonly property string runtimeDir:
        Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string statsPath: runtimeDir + "/qs-startmenu-stats.json"

    property string clockText: "--:--"
    property string dateText: ""
    property string netText: "net --"
    property string cpuText: "cpu --"
    property string memText: "mem --"
    property string gpuText: "gpu --"
    property string tempText: "temp --"

    function refreshClock() {
        const now = new Date()
        clockText = Qt.formatDateTime(now, "HH:mm:ss")
        // ISO-style date: 2026-07-29
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

    // refresh when section is created; shell can also call refreshStats on menu open
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
        anchors.fill: parent
        anchors.margins: 8
        spacing: 6

        // ── 1. tray icons ──
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
                        color: "#11111b"
                        border.color: "#45475a"
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
                            color: "#cdd6f4"
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
                                if (modelData.onlyMenu && root.menuWindow) {
                                    const p = mapToItem(null, mouse.x, mouse.y)
                                    modelData.display(root.menuWindow, Math.round(p.x), Math.round(p.y))
                                } else {
                                    modelData.activate()
                                }
                            } else if (mouse.button === Qt.MiddleButton) {
                                modelData.secondaryActivate()
                            } else if (mouse.button === Qt.RightButton && root.menuWindow) {
                                const p = mapToItem(null, mouse.x, mouse.y)
                                modelData.display(root.menuWindow, Math.round(p.x), Math.round(p.y))
                            }
                        }

                        onWheel: wheel => modelData.scroll(wheel.angleDelta.y, false)
                    }
                }
            }
        }

        // ── 2. volume ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            readonly property var sinkAudio: Pipewire.defaultAudioSink?.audio ?? null
            readonly property real vol: {
                const a = sinkAudio
                if (!a) return 0
                const v = a.volume
                return (typeof v === "number" && isFinite(v)) ? Math.max(0, Math.min(1, v)) : 0
            }
            readonly property bool muted: sinkAudio ? !!sinkAudio.muted : true

            Text {
                text: {
                    if (!parent.sinkAudio || parent.muted || parent.vol === 0) return "MUTE"
                    return "VOL"
                }
                color: "#cdd6f4"
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
                color: "#313244"
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * (parent.parent.muted ? 0 : parent.parent.vol)
                    radius: parent.radius
                    color: "#89b4fa"
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => {
                        const a = parent.parent.sinkAudio
                        if (!a) return
                        a.volume = Math.max(0, Math.min(1, mouse.x / width))
                        a.muted = false
                    }
                    onPositionChanged: mouse => {
                        if (!pressed) return
                        const a = parent.parent.sinkAudio
                        if (!a) return
                        a.volume = Math.max(0, Math.min(1, mouse.x / width))
                        a.muted = false
                    }
                }
            }

            Text {
                text: !parent.sinkAudio ? "--%"
                      : Math.round((parent.muted ? 0 : parent.vol) * 100) + "%"
                color: "#a6adc8"
                font.pixelSize: 11
                Layout.preferredWidth: 36
                horizontalAlignment: Text.AlignRight
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: "#313244"
        }

        // ── 3. stats (plain labels, no nerd icons) ──
        Flow {
            Layout.fillWidth: true
            spacing: 12

            Text {
                text: root.cpuText
                color: "#cdd6f4"
                font.pixelSize: 14
            }
            Text {
                text: root.memText
                color: "#cdd6f4"
                font.pixelSize: 14
            }
            Text {
                text: root.gpuText
                color: "#cdd6f4"
                font.pixelSize: 14
            }
            Text {
                text: root.netText
                color: "#cdd6f4"
                font.pixelSize: 14
            }
        }

        // ── 4. time + ISO date ──
        RowLayout {
            Layout.fillWidth: true
            Text {
                text: root.clockText
                color: "#89b4fa"
                font.pixelSize: 14
                font.bold: false
            }
            Text {
                text: root.dateText
                color: "#89b4fa"
                font.pixelSize: 14
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
            }
        }
    }
}
