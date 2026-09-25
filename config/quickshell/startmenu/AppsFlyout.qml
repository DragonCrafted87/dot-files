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
    property var apps: []
    property string title: controller ? controller.flyoutTitle : ""
    readonly property int rowStep: 36
    readonly property int titleH: 16
    readonly property int chromeH: 16 + 4 + titleH
    readonly property int appCount: Array.isArray(root.apps) ? root.apps.length : 0
    implicitHeight: chromeH + Math.max(1, root.appCount) * rowStep

    function reloadApps() {
        const next = root.controller ? root.controller.collectApps() : []
        root.apps = next
        appModel.values = next
        if (appList.contentY !== 0)
            appList.contentY = 0
    }

    onControllerChanged: root.reloadApps()
    Component.onCompleted: root.reloadApps()

    Connections {
        target: root.controller
        function onFilterCatChanged() { root.reloadApps() }
        function onSearchTextChanged() { root.reloadApps() }
        function onHoveredCatChanged() { root.reloadApps() }
        function onPinnedCatChanged() { root.reloadApps() }
    }

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
            Layout.preferredHeight: 0
            implicitHeight: 0
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            flickDeceleration: 10000
            maximumFlickVelocity: 8000
            model: ScriptModel {
                id: appModel
                values: root.apps
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
