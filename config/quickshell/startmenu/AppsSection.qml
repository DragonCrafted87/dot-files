import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Widgets
import Quickshell.Hyprland

Rectangle {
    id: root
    radius: 8
    color: "#181825"
    border.color: "#313244"
    border.width: 1

    signal appLaunched()

    property int openWorkspaceId: 1
    property int categoryWidth: 148
    property int flyoutWidth: 240
    readonly property bool flyoutOpen: searchActive || hoveredCat !== "" || pinnedCat !== ""
    readonly property bool searchActive: searchField.text.trim().length > 0
    property string hoveredCat: ""
    property string pinnedCat: ""
    property string hoveredLabel: "All"

    implicitWidth: categoryWidth + 16 + (flyoutOpen ? flyoutWidth + 8 : 0)

    function appSearchBlob(a) {
        const keywords = Array.isArray(a.keywords) ? a.keywords.join(" ") : (a.keywords || "")
        return [
            a.name || "",
            a.genericName || "",
            a.comment || "",
            a.id || "",
            keywords
        ].join(" ").toLowerCase()
    }

    function collectApps() {
        const q = searchField.text.trim().toLowerCase()
        const selectedCat = root.searchActive ? "" : (root.pinnedCat || root.hoveredCat)
        let apps = []
        try {
            apps = Array.from(DesktopEntries.applications.values)
        } catch (e) {
            apps = []
        }
        const seen = {}
        apps = apps.filter(a => {
            if (!a || a.noDisplay) return false
            const id = a.id || a.name || ""
            if (!id || seen[id]) return false
            seen[id] = true
            return true
        })
        return apps.filter(a => {
            if (selectedCat) {
                const cats = a.categories || []
                if (!cats.includes(selectedCat)) return false
            }
            if (!q) return true
            return root.appSearchBlob(a).includes(q)
        }).sort((a, b) => (a.name || "").localeCompare(b.name || ""))
    }

    function entryNeedles(entry) {
        const id = (entry.id || "").toLowerCase()
        const last = id.split(".").pop()
        return [
            (entry.startupClass || "").toLowerCase(),
            id,
            last,
            (entry.name || "").toLowerCase()
        ].filter(s => s && s.length > 1)
    }

    function findRunning(entry) {
        const needles = root.entryNeedles(entry)
        if (!needles.length) return null
        let tops = []
        try {
            Hyprland.refreshToplevels()
            tops = Array.from(Hyprland.toplevels.values)
        } catch (e) {
            tops = []
        }
        for (let i = 0; i < tops.length; i++) {
            const t = tops[i]
            if (!t) continue
            const ipc = t.lastIpcObject || {}
            const cls = String(ipc.class || ipc.initialClass || "").toLowerCase()
            const title = String(t.title || ipc.title || "").toLowerCase()
            for (let n = 0; n < needles.length; n++) {
                const needle = needles[n]
                if (cls === needle || cls.indexOf(needle) !== -1 || title.indexOf(needle) !== -1)
                    return t
            }
        }
        return null
    }

    function launchOrSwitch(entry) {
        if (!entry) return
        const ws = root.openWorkspaceId || 1
        const running = root.findRunning(entry)
        if (running && running.address) {
            Hyprland.dispatch("movetoworkspace " + ws + ",address:" + running.address)
            Hyprland.dispatch("focuswindow address:" + running.address)
        } else {
            Hyprland.dispatch("workspace " + ws)
            entry.execute()
        }
        root.appLaunched()
    }

    function openCategory(cat, label) {
        root.hoveredCat = cat
        root.hoveredLabel = label
    }

    function pinCategory(cat, label) {
        if (root.pinnedCat === cat && !root.searchActive) {
            root.pinnedCat = ""
            return
        }
        root.pinnedCat = cat
        root.hoveredCat = cat
        root.hoveredLabel = label
        searchField.text = ""
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 8

        ColumnLayout {
            Layout.preferredWidth: root.categoryWidth
            Layout.fillHeight: true
            spacing: 6

            TextField {
                id: searchField
                Layout.fillWidth: true
                placeholderText: "Search apps…"
                color: "#cdd6f4"
                placeholderTextColor: "#6c7086"
                background: Rectangle {
                    radius: 6
                    color: "#11111b"
                    border.color: searchField.activeFocus ? "#89b4fa" : "#313244"
                    border.width: 1
                }
                Keys.onEscapePressed: root.appLaunched()
                onTextChanged: {
                    if (text.trim().length)
                        root.hoveredLabel = "Search"
                }
            }

            ListView {
                id: catList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2

                model: ListModel {
                    ListElement { label: "All"; cat: "" }
                    ListElement { label: "Accessories"; cat: "Utility" }
                    ListElement { label: "Development"; cat: "Development" }
                    ListElement { label: "Games"; cat: "Game" }
                    ListElement { label: "Graphics"; cat: "Graphics" }
                    ListElement { label: "Internet"; cat: "Network" }
                    ListElement { label: "Multimedia"; cat: "AudioVideo" }
                    ListElement { label: "Office"; cat: "Office" }
                    ListElement { label: "Settings"; cat: "Settings" }
                    ListElement { label: "System"; cat: "System" }
                }

                delegate: Rectangle {
                    required property string label
                    required property string cat
                    required property int index
                    width: catList.width
                    height: 30
                    radius: 6
                    readonly property bool selected: {
                        if (root.searchActive) return false
                        const current = root.pinnedCat !== "" ? root.pinnedCat : root.hoveredCat
                        return current === cat && (cat !== "" || root.flyoutOpen)
                    }
                    color: selected ? "#89b4fa" : (catMouse.containsMouse ? "#313244" : "transparent")

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: label
                        color: parent.selected ? "#1e1e2e" : "#cdd6f4"
                        font.pixelSize: 12
                        font.bold: parent.selected
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        text: "›"
                        color: parent.selected ? "#1e1e2e" : "#6c7086"
                        font.pixelSize: 14
                    }

                    MouseArea {
                        id: catMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.openCategory(cat, label)
                        onClicked: root.pinCategory(cat, label)
                    }
                }
            }
        }

        Rectangle {
            visible: root.flyoutOpen
            Layout.preferredWidth: root.flyoutWidth
            Layout.fillHeight: true
            radius: 8
            color: "#11111b"
            border.color: "#313244"
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 6
                spacing: 4

                Text {
                    text: root.searchActive ? "Search" : root.hoveredLabel
                    color: "#a6adc8"
                    font.pixelSize: 11
                    font.bold: true
                }

                ListView {
                    id: appList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: ScriptModel {
                        values: {
                            const _dep = DesktopEntries.applications.values
                            const _q = searchField.text
                            const _c = root.hoveredCat + root.pinnedCat
                            return root.collectApps()
                        }
                    }

                    delegate: Rectangle {
                        required property var modelData
                        width: appList.width
                        height: 34
                        radius: 6
                        color: appMouse.containsMouse ? "#313244" : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            spacing: 8

                            IconImage {
                                Layout.preferredWidth: 22
                                Layout.preferredHeight: 22
                                source: Quickshell.iconPath(modelData.icon, "application-x-executable")
                            }

                            Text {
                                Layout.fillWidth: true
                                text: modelData.name || modelData.id
                                color: "#cdd6f4"
                                font.pixelSize: 13
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: appMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.launchOrSwitch(modelData)
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: appList.count === 0
                        text: "No apps"
                        color: "#6c7086"
                        font.pixelSize: 11
                    }
                }
            }
        }
    }
}
