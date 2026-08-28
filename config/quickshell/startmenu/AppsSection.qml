import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Widgets

Rectangle {
    id: root
    radius: 8
    color: "#181825"
    border.color: "#313244"
    border.width: 1

    signal appLaunched()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
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
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 6

            ListView {
                id: catList
                Layout.preferredWidth: 110
                Layout.fillHeight: true
                clip: true
                spacing: 2
                currentIndex: 0

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
                    height: 28
                    radius: 6
                    color: catList.currentIndex === index
                           ? "#89b4fa"
                           : (catMouse.containsMouse ? "#313244" : "transparent")

                    Text {
                        anchors.centerIn: parent
                        text: label
                        color: catList.currentIndex === index ? "#1e1e2e" : "#cdd6f4"
                        font.pixelSize: 12
                        font.bold: catList.currentIndex === index
                    }

                    MouseArea {
                        id: catMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            catList.currentIndex = index
                            searchField.text = ""
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                color: "#313244"
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
                        const q = searchField.text.trim().toLowerCase()
                        const selectedCat = catList.model.get(catList.currentIndex).cat

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
                            const name = (a.name || "").toLowerCase()
                            const generic = (a.genericName || "").toLowerCase()
                            const comment = (a.comment || "").toLowerCase()
                            return name.includes(q) || generic.includes(q) || comment.includes(q)
                        }).sort((a, b) => (a.name || "").localeCompare(b.name || ""))
                    }
                }

                delegate: Rectangle {
                    required property var modelData
                    width: appList.width
                    height: 36
                    radius: 6
                    color: appMouse.containsMouse ? "#313244" : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        spacing: 8

                        IconImage {
                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 24
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
                        onClicked: {
                            modelData.execute()
                            root.appLaunched()
                        }
                    }
                }
            }
        }
    }
}
