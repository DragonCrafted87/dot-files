//@ pragma UseQApplication
//@ pragma ShellId startmenu
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire

ShellRoot {
    id: root
    property bool menuOpen: false

    property int menuW: 380
    property int menuH: 1080
    property int menuMarginLeft: 8
    property int menuMarginTop: 8

    readonly property string cursorPath:
        (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-startmenu-cursor.txt"

    function openAtCursor() {
        cursorProc.running = false
        cursorProc.running = true
    }

    function applyCursorPlacement(raw) {
        // raw: first line "x, y" from hyprctl cursorpos
        // rest: monitors JSON
        try {
            const lines = raw.trim().split("\n")
            const posLine = lines[0] || "0, 0"
            const parts = posLine.split(",")
            const globalX = parseInt(parts[0].trim(), 10) || 0
            const globalY = parseInt(parts[1].trim(), 10) || 0

            const monJson = lines.slice(1).join("\n")
            const monitors = JSON.parse(monJson)
            let mon = monitors.find(m => m.focused) || monitors[0]
            if (!mon) {
                root.menuMarginLeft = 8
                root.menuMarginTop = 8
                root.menuOpen = true
                return
            }

            // cursor relative to focused monitor
            let localX = globalX - mon.x
            let localY = globalY - mon.y
            const monW = mon.width
            const monH = mon.height

            // place menu top-left near cursor; clamp so it stays on screen
            let left = localX
            let top = localY
            if (left + root.menuW > monW)
                left = Math.max(0, monW - root.menuW - 8)
            if (top + root.menuH > monH)
                top = Math.max(0, monH - root.menuH - 8)
            if (left < 0) left = 8
            if (top < 0) top = 8

            root.menuMarginLeft = left
            root.menuMarginTop = top
            root.menuOpen = true

            taskbarSection.refresh()
        } catch (e) {
            console.log("cursor place error:", e)

            root.menuMarginLeft = 8
            root.menuMarginTop = 8
            root.menuOpen = true

            taskbarSection.refresh()
        }
    }

    IpcHandler {
        target: "startmenu"
        function toggle(): void {
            if (root.menuOpen)
                root.menuOpen = false
            else
                root.openAtCursor()
        }
        function open(): void { root.openAtCursor() }
        function close(): void { root.menuOpen = false }
    }

    Process {
        id: cursorProc
        command: [
            "sh", "-c",
            // one file: line1 = cursor, rest = monitors json
            "echo \"$(hyprctl cursorpos)\" > '" + root.cursorPath + "'; " +
            "hyprctl monitors -j >> '" + root.cursorPath + "'"
        ]
        running: false
        onExited: {
            cursorFile.path = root.cursorPath
            cursorFile.reload()
        }
    }

    FileView {
        id: cursorFile
        onLoaded: root.applyCursorPlacement(cursorFile.text())
    }

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    PanelWindow {
        id: menuWindow
        visible: root.menuOpen
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.menuOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        WlrLayershell.namespace: "qs-startmenu"

        // only top+left so margins act as free position
        anchors {
            left: true
            top: true
        }
        margins {
            left: root.menuMarginLeft
            top: root.menuMarginTop
        }

        width: root.menuW
        height: root.menuH
        color: "transparent"

        Rectangle {
            id: panel
            anchors.fill: parent
            radius: 12
            color: "#1e1e2e"
            border.color: "#45475a"
            border.width: 1
            focus: root.menuOpen
            Keys.onEscapePressed: root.menuOpen = false

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8

                AppsSection {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: 340
                    onAppLaunched: root.menuOpen = false
                }

                TaskbarSection {
                    id: taskbarSection
                    Layout.fillWidth: true
                    Layout.preferredHeight: 140
                    minimizedOnly: true
                    onWindowFocused: root.menuOpen = false
                }

                TraySection {
                    id: traySection
                    Layout.fillWidth: true
                    Layout.preferredHeight: 150
                    menuWindow: menuWindow
                }

                PowerSection {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    onActionTriggered: root.menuOpen = false
                }
            }
        }
    }

    onMenuOpenChanged: {
        if (root.menuOpen) {
            taskbarSection.refresh()
            traySection.refreshStats()
        }
    }
}
