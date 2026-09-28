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
    property bool chromeVisible: true
    property bool dismissVisible: false

    property int menuBaseW: 380
    property int menuMarginLeft: 8
    property int menuMarginTop: 8
    property int openWorkspaceId: 1
    property int monitorWidth: 1920
    property int monitorHeight: 1080
    property int flyoutWidth: 260
    property int flyoutGap: 8
    readonly property int menuPad: 44
    readonly property int powerH: 52
    readonly property int menuMaxH: Math.max(280, monitorHeight - 16)
    readonly property int menuNaturalH: menuPad
        + appsSection.implicitHeight
        + taskbarSection.implicitHeight
        + traySection.implicitHeight
        + powerH
    readonly property int menuH: Math.max(280, Math.min(menuMaxH, menuNaturalH))
    readonly property bool menuCapped: menuNaturalH > menuMaxH

    readonly property bool flyoutOpen: menuOpen && chromeVisible && appsSection.flyoutOpen
    readonly property bool flyoutOnLeft: (menuMarginLeft + menuBaseW + flyoutGap + flyoutWidth) > (monitorWidth - 8)
    readonly property int flyoutMarginLeft: flyoutOnLeft
        ? Math.max(8, menuMarginLeft - flyoutWidth - flyoutGap)
        : (menuMarginLeft + menuBaseW + flyoutGap)
    readonly property int flyoutContentY: Math.max(0, Math.round(appsSection.y + appsSection.flyoutAlignY))
    readonly property int flyoutLayerHeight: Math.max(1, monitorHeight - menuMarginTop - 8)

    readonly property string cursorPath:
        (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-startmenu-cursor.txt"

    function sizeForMonitor(mon) {
        const h = mon.height || 1080
        const w = mon.width || 1920
        root.monitorWidth = w
        root.monitorHeight = h
        root.menuBaseW = Math.max(380, Math.min(460, Math.round(w * 0.22)))
    }

    function openAtCursor() {
        root.chromeVisible = true
        cursorProc.running = false
        cursorProc.running = true
    }

    function closeMenu() {
        root.dismissVisible = false
        root.menuOpen = false
        root.chromeVisible = true
    }

    function applyCursorPlacement(raw) {
        const wasOpen = root.menuOpen
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
                if (wasOpen)
                    taskbarSection.refresh()
                return
            }

            root.sizeForMonitor(mon)
            root.openWorkspaceId = (mon.activeWorkspace && mon.activeWorkspace.id)
                ? mon.activeWorkspace.id
                : 1

            let localX = globalX - mon.x
            let localY = globalY - mon.y
            const monW = mon.width
            const monH = mon.height

            let left = localX
            let top = localY
            if (left + root.menuBaseW > monW)
                left = Math.max(8, monW - root.menuBaseW - 8)
            if (top + root.menuH > monH)
                top = Math.max(8, monH - root.menuH - 8)
            if (left < 0) left = 8
            if (top < 0) top = 8

            root.menuMarginLeft = left
            root.menuMarginTop = top
            root.menuOpen = true
            root.chromeVisible = true
            if (wasOpen)
                taskbarSection.refresh()
        } catch (e) {
            console.log("cursor place error:", e)
            root.menuMarginLeft = 8
            root.menuMarginTop = 8
            root.menuOpen = true
            if (wasOpen)
                taskbarSection.refresh()
        }
    }

    IpcHandler {
        target: "startmenu"
        function toggle(): void {
            if (root.menuOpen)
                root.closeMenu()
            else
                root.openAtCursor()
        }
        function open(): void { root.openAtCursor() }
        function close(): void { root.closeMenu() }
    }

    Process {
        id: cursorProc
        command: [
            "sh", "-c",
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

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            screen: modelData
            visible: root.dismissVisible
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "qs-startmenu-dismiss"
            color: "transparent"

            anchors {
                left: true
                right: true
                top: true
                bottom: true
            }

            MouseArea {
                anchors.fill: parent
                onPressed: Qt.callLater(root.closeMenu)
            }
        }
    }

    PanelWindow {
        id: menuWindow
        visible: root.menuOpen
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.menuOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        WlrLayershell.namespace: "qs-startmenu"

        anchors {
            left: true
            top: true
        }
        margins {
            left: root.menuMarginLeft
            top: root.menuMarginTop
        }

        width: root.menuBaseW
        height: root.menuH
        color: "transparent"

        Rectangle {
            id: panel
            anchors.fill: parent
            radius: 12
            color: "#000000"
            border.color: "#555753"
            border.width: 1
            visible: root.chromeVisible
            focus: root.menuOpen && root.chromeVisible
            Keys.onEscapePressed: root.closeMenu()

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8

                AppsSection {
                    id: appsSection
                    Layout.fillWidth: true
                    Layout.fillHeight: root.menuCapped
                    Layout.preferredHeight: implicitHeight
                    Layout.minimumHeight: root.menuCapped ? 160 : implicitHeight
                    Layout.maximumHeight: implicitHeight
                    openWorkspaceId: root.openWorkspaceId
                    categoryWidth: Math.max(132, root.menuBaseW - 24)
                    onAppLaunched: root.closeMenu()
                }

                TaskbarSection {
                    id: taskbarSection
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.preferredHeight: implicitHeight
                    Layout.minimumHeight: implicitHeight
                    Layout.maximumHeight: implicitHeight
                    minimizedOnly: true
                    targetWorkspaceId: root.openWorkspaceId
                    onWindowFocused: root.closeMenu()
                }

                TraySection {
                    id: traySection
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.preferredHeight: implicitHeight
                    Layout.minimumHeight: implicitHeight
                    Layout.maximumHeight: implicitHeight
                    menuWindow: menuWindow
                    onTrayMenuRequested: root.chromeVisible = false
                }

                PowerSection {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.preferredHeight: root.powerH
                    Layout.minimumHeight: root.powerH
                    Layout.maximumHeight: root.powerH
                    onActionTriggered: root.closeMenu()
                }
            }
        }
    }

    PanelWindow {
        id: flyoutWindow
        visible: root.flyoutOpen
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qs-startmenu-flyout"

        anchors {
            left: true
            top: true
        }
        margins {
            left: root.flyoutMarginLeft
            top: root.menuMarginTop
        }

        width: root.flyoutWidth
        height: root.flyoutLayerHeight
        color: "transparent"
        mask: Region {
            id: flyoutMask
            item: appsFlyout
        }

        AppsFlyout {
            id: appsFlyout
            x: 0
            y: root.flyoutContentY
            width: root.flyoutWidth
            height: Math.min(implicitHeight, Math.max(1, flyoutWindow.height - y))
            controller: appsSection
            onHeightChanged: flyoutMask.changed()
            onYChanged: flyoutMask.changed()
        }
    }

    onMenuOpenChanged: {
        if (root.menuOpen) {
            root.chromeVisible = true
            taskbarSection.refresh()
            traySection.refreshStats()
            Qt.callLater(() => {
                if (root.menuOpen)
                    root.dismissVisible = true
            })
        } else {
            root.dismissVisible = false
            root.chromeVisible = true
        }
    }
}
