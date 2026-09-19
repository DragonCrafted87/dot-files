import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Widgets

Rectangle {
    id: root
    radius: 8
    color: "#000000"
    border.color: "#555753"
    border.width: 1

    property var controller
    property string title: controller ? controller.flyoutTitle : ""
    property string refreshKey: controller ? (controller.filterCat + "|" + controller.searchText) : ""
    readonly property int rowStep: 36

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 4

        Text {
            text: root.title
            color: "#D3D7CF"
            font.pixelSize: 11
            font.bold: true
        }

        ListView {
            id: appList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            flickDeceleration: 10000
            maximumFlickVelocity: 8000
            model: ScriptModel {
                values: {
                    const _k = root.refreshKey
                    if (!root.controller)
                        return []
                    return root.controller.collectApps()
                }
            }

            function scrollRows(dir) {
                const maxY = Math.max(0, contentHeight - height)
                contentY = Math.max(0, Math.min(maxY, contentY + (dir * root.rowStep)))
            }

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.pixelDelta.y
                    if (delta === 0)
                        return
                    appList.scrollRows(delta > 0 ? -1 : 1)
                    event.accepted = true
                }
            }

            delegate: Rectangle {
                required property var modelData
                width: appList.width
                height: 34
                radius: 6
                color: appMouse.containsMouse ? "#555753" : "transparent"

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
                        color: "#EEEEEC"
                        font.pixelSize: 13
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: appMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: event => {
                        if (event.button === Qt.RightButton) {
                            appMenu.popup()
                            return
                        }
                        root.controller.launchOrSwitch(modelData)
                    }
                }

                Menu {
                    id: appMenu
                    MenuItem {
                        text: "Open desktop file"
                        onTriggered: root.controller.openDesktopFile(modelData)
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: appList.count === 0
                text: "No apps"
                color: "#555753"
                font.pixelSize: 11
            }
        }
    }
}
