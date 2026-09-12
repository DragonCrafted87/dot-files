import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Rectangle {
    id: root
    radius: 8
    color: "#181825"
    border.color: "#313244"
    border.width: 1

    signal actionTriggered()

    readonly property string sessionCtl: Quickshell.env("HOME") + "/.config/hypr/scripts/session-control.sh"

    Process {
        id: powerProc
        command: []
    }

    function runAction(action) {
        console.log("power:", action)
        powerProc.command = ["bash", root.sessionCtl, action]
        powerProc.startDetached()
        root.actionTriggered()
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 4

        Repeater {
            model: ListModel {
                ListElement { label: "Lock";     action: "lock" }
                ListElement { label: "Logout";   action: "logout" }
                ListElement { label: "Suspend";  action: "suspend" }
                ListElement { label: "Reboot";   action: "reboot" }
                ListElement { label: "Shutdown"; action: "shutdown" }
            }

            delegate: Rectangle {
                required property string label
                required property string action
                required property int index

                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 6
                color: powerMouse.containsMouse ? "#313244" : "transparent"

                Column {
                    anchors.centerIn: parent
                    spacing: 2

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: label
                        color: index === 4 ? "#f38ba8" : "#a6adc8"
                        font.pixelSize: 14
                    }
                }

                MouseArea {
                    id: powerMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.runAction(action)
                }
            }
        }
    }
}
