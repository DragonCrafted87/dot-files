import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

Rectangle {
    id: root
    radius: 8
    color: "#000000"
    border.color: "#555753"
    border.width: 1

    signal windowFocused()
    property bool minimizedOnly: true
    property bool autoFlipping: false
    property int targetWorkspaceId: 1
    property int refreshReq: 0
    property int refreshSeen: 0
    readonly property int rowHeight: 32
    readonly property int listGap: 2
    readonly property int headerH: 18
    readonly property int maxVisibleRows: 8
    implicitHeight: {
        const rows = Math.max(1, Math.min(winModel.count, maxVisibleRows))
        return 16 + 4 + headerH + rows * (rowHeight + listGap)
    }

    readonly property string runtimeDir:
        Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"

    ListModel { id: winModel }

    function clientsPath(gen) {
        return root.runtimeDir + "/qs-startmenu-clients-" + gen + ".json"
    }

    function refresh() {
        root.refreshReq++
        if (!clientsProc.running)
            refreshKick.start()
    }

    function isMinimizedClient(c) {
        const ws = (c.workspace && c.workspace.name) ? String(c.workspace.name) : ""
        return ws.indexOf("special") === 0 || ws.indexOf("minimized") !== -1
    }

    function iconNameForClass(cls) {
        const raw = String(cls || "")
        const c = raw.toLowerCase()
        if (!c)
            return "application-x-executable"
        // Microsoft Code: Hyprland app id is "code" / "com.microsoft.VSCode";
        // the desktop file Icon= is "vscode".
        if (c === "code" || c === "code-url-handler" || c === "com.microsoft.vscode")
            return "vscode"
        try {
            const apps = Array.from(DesktopEntries.applications.values)
            for (let i = 0; i < apps.length; i++) {
                const a = apps[i]
                if (!a || !a.icon)
                    continue
                const id = String(a.id || "").toLowerCase()
                const startup = String(a.startupClass || "").toLowerCase()
                const last = id.split(".").pop()
                if (c === startup || c === id || (last && c === last))
                    return a.icon
            }
        } catch (e) {
        }
        return raw
    }

    function parseClients(raw) {
        winModel.clear()
        if (!raw || !String(raw).trim()) {
            console.log("clients empty payload")
            if (root.minimizedOnly)
                root.showAllWindows()
            return
        }
        try {
            const clients = JSON.parse(raw)
            const usable = clients.filter(c => c && c.address)
            const minimized = usable.filter(c => root.isMinimizedClient(c))
            let filtered
            if (root.minimizedOnly) {
                if (minimized.length === 0) {
                    root.showAllWindows()
                    filtered = usable
                } else {
                    filtered = minimized
                }
            } else {
                filtered = usable
            }
            filtered.sort((a, b) => {
                const ca = (a.initialClass || a.class || "").toLowerCase()
                const cb = (b.initialClass || b.class || "").toLowerCase()
                if (ca !== cb) return ca.localeCompare(cb)
                return (a.title || "").localeCompare(b.title || "")
            })
            for (let i = 0; i < filtered.length; i++) {
                const c = filtered[i]
                const cls = c.initialClass || c.class || ""
                winModel.append({
                    title: c.title || "(no title)",
                    cls: cls,
                    iconName: root.iconNameForClass(cls),
                    wsName: (c.workspace && c.workspace.name) ? String(c.workspace.name) : "?",
                    address: String(c.address)
                })
            }
        } catch (e) {
            console.log("clients parse error:", e)
        }
    }

    function restoreWindow(address) {
        if (!address) return
        const ws = root.targetWorkspaceId || 1
        restoreProc.command = [
            "sh", "-c",
            'addr="' + address + '"; ws="' + ws + '"; ' +
            'hyprctl --batch "' +
            "dispatch movetoworkspace $ws,address:$addr; " +
            "dispatch focuswindow address:$addr; " +
            "dispatch togglespecialworkspace minimized" +
            '"; ' +
            'sleep 0.08; ' +
            'current_special=$(hyprctl activeworkspace -j | jq -r ".name // \\"\\""); ' +
            'if echo "$current_special" | grep -q minimized; then ' +
            '  hyprctl dispatch togglespecialworkspace minimized; ' +
            'fi'
        ]
        restoreProc.running = true
        root.windowFocused()
    }

    function closeWindow(address) {
        if (!address) return
        closeProc.command = [
            "sh", "-c",
            'hyprctl dispatch closewindow address:"' + address + '"'
        ]
        closeProc.running = true
    }

    Timer {
        id: refreshKick
        interval: 30
        repeat: false
        onTriggered: {
            if (clientsProc.running)
                return
            root.refreshSeen = root.refreshReq
            const path = root.clientsPath(root.refreshSeen)
            clientsProc.command = [
                "sh", "-c",
                "hyprctl clients -j > '" + path + "'"
            ]
            clientsProc.running = true
        }
    }

    Process {
        id: clientsProc
        command: ["true"]
        running: false
        onExited: {
            const req = root.refreshSeen
            clientsFile.path = root.clientsPath(req)
            clientsFile.reload()
            if (root.refreshReq !== req)
                refreshKick.restart()
        }
    }

    FileView {
        id: clientsFile
        onLoaded: root.parseClients(clientsFile.text())
    }

    Process {
        id: restoreProc
        command: []
    }

    Process {
        id: closeProc
        command: []
        onExited: root.refresh()
    }

    function showAllWindows() {
        if (!root.minimizedOnly)
            return
        root.autoFlipping = true
        root.minimizedOnly = false
        root.autoFlipping = false
    }

    onMinimizedOnlyChanged: {
        if (!root.autoFlipping)
            root.refresh()
    }
    Component.onCompleted: root.refresh()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 4

        RowLayout {
            Layout.fillWidth: true

            Text {
                text: root.minimizedOnly ? "Minimized" : "Windows"
                color: "#D3D7CF"
                font.pixelSize: 11
                font.bold: true
            }

            Item { Layout.fillWidth: true }

            Text {
                text: "↻"
                color: refreshMouse.containsMouse ? "#729FCF" : "#555753"
                font.pixelSize: 12
                MouseArea {
                    id: refreshMouse
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.refresh()
                }
            }

            Text {
                text: root.minimizedOnly ? "All" : "Min"
                color: toggleMouse.containsMouse ? "#729FCF" : "#555753"
                font.pixelSize: 10
                MouseArea {
                    id: toggleMouse
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.minimizedOnly = !root.minimizedOnly
                }
            }
        }

        ListView {
            id: winList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            model: winModel

            delegate: Rectangle {
                required property string title
                required property string cls
                required property string iconName
                required property string wsName
                required property string address

                width: winList.width
                height: root.rowHeight
                radius: 6
                color: winMouse.containsMouse ? "#555753" : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    spacing: 8

                    IconImage {
                        Layout.preferredWidth: 18
                        Layout.preferredHeight: 18
                        source: Quickshell.iconPath(iconName, "application-x-executable")
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Text {
                            Layout.fillWidth: true
                            text: title
                            color: "#EEEEEC"
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: (cls ? cls + "  ·  " : "") + wsName
                            color: "#555753"
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }
                    }
                }

                MouseArea {
                    id: winMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: event => {
                        if (event.button === Qt.RightButton) {
                            winMenu.popup()
                            return
                        }
                        root.restoreWindow(address)
                    }
                }

                Menu {
                    id: winMenu
                    MenuItem {
                        text: "Close"
                        onTriggered: root.closeWindow(address)
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: winList.count === 0
                text: root.minimizedOnly ? "No minimized windows" : "No windows"
                color: "#555753"
                font.pixelSize: 11
            }
        }
    }
}
