import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

Rectangle {
    id: root
    radius: 8
    color: "#181825"
    border.color: "#313244"
    border.width: 1

    signal windowFocused()
    property bool minimizedOnly: true

    readonly property string clientsPath:
        (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-startmenu-clients.json"

    ListModel { id: winModel }

    function refresh() {
        clientsFile.path = ""
        clientsProc.running = false
        clientsProc.running = true
    }

    function parseClients(raw) {
        winModel.clear()
        console.log("clients raw length:", raw ? raw.length : 0)
        try {
            const clients = JSON.parse(raw)
            console.log("clients count:", clients.length)
            const filtered = clients.filter(c => {
                if (!c || !c.address) return false
                const ws = (c.workspace && c.workspace.name) ? String(c.workspace.name) : ""
                if (root.minimizedOnly) {
                    return ws.indexOf("special") === 0 || ws.indexOf("minimized") !== -1
                }
                return true
            })
            console.log("filtered count:", filtered.length)
            filtered.sort((a, b) => {
                const ca = (a.initialClass || a.class || "").toLowerCase()
                const cb = (b.initialClass || b.class || "").toLowerCase()
                if (ca !== cb) return ca.localeCompare(cb)
                return (a.title || "").localeCompare(b.title || "")
            })
            for (let i = 0; i < filtered.length; i++) {
                const c = filtered[i]
                winModel.append({
                    title: c.title || "(no title)",
                    cls: c.initialClass || c.class || "",
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
        restoreProc.command = [
            "sh", "-c",
            'addr="' + address + '"; ' +
            'target_ws=$(hyprctl monitors -j | jq -r ".[0].activeWorkspace.id"); ' +
            'hyprctl --batch "' +
            "dispatch movetoworkspacesilent $target_ws,address:$addr; " +
            "dispatch focuswindow address:$addr; " +
            "dispatch togglespecialworkspace minimized" +
            '"; ' +
            'sleep 0.08; ' +
            'current_special=$(hyprctl monitors -j | jq -r ".[0].specialWorkspace.name // \\"\\""); ' +
            'if echo "$current_special" | grep -q minimized; then ' +
            '  hyprctl dispatch togglespecialworkspace minimized; ' +
            'fi'
        ]
        restoreProc.running = true
        root.windowFocused()
    }

    Process {
        id: clientsProc
        command: [
            "sh", "-c",
            "hyprctl clients -j > '" + root.clientsPath + "' 2>/dev/null || echo '[]' > '" + root.clientsPath + "'"
        ]
        running: true
        onExited: {
            clientsFile.path = root.clientsPath
            clientsFile.reload()
        }
    }

    FileView {
        id: clientsFile
        // path assigned after process exits
        onLoaded: {
            // text() is a function, not a property
            root.parseClients(clientsFile.text())
        }
    }

    Process {
        id: restoreProc
        command: []
    }

    onMinimizedOnlyChanged: root.refresh()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 4

        RowLayout {
            Layout.fillWidth: true

            Text {
                text: root.minimizedOnly ? "Minimized" : "Windows"
                color: "#a6adc8"
                font.pixelSize: 11
                font.bold: true
            }

            Item { Layout.fillWidth: true }

            Text {
                text: "↻"
                color: refreshMouse.containsMouse ? "#89b4fa" : "#6c7086"
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
                color: toggleMouse.containsMouse ? "#89b4fa" : "#6c7086"
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
                required property string wsName
                required property string address

                width: winList.width
                height: 32
                radius: 6
                color: winMouse.containsMouse ? "#313244" : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    spacing: 8

                    IconImage {
                        Layout.preferredWidth: 18
                        Layout.preferredHeight: 18
                        source: Quickshell.iconPath(cls, "application-x-executable")
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Text {
                            Layout.fillWidth: true
                            text: title
                            color: "#cdd6f4"
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: (cls ? cls + "  ·  " : "") + wsName
                            color: "#6c7086"
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }
                    }
                }

                MouseArea {
                    id: winMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.restoreWindow(address)
                }
            }

            Text {
                anchors.centerIn: parent
                visible: winList.count === 0
                text: root.minimizedOnly ? "No minimized windows" : "No windows"
                color: "#6c7086"
                font.pixelSize: 11
            }
        }
    }
}
