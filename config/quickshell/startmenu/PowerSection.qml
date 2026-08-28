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

    Process {
        id: powerProc
        command: []
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 4

        Repeater {
            model: ListModel {
                ListElement { label: "Lock";     icon: ""; cmd: "hyprlock" }
                ListElement { label: "Logout";   icon: ""; cmd: "hyprctl dispatch exit" }
                ListElement { label: "Suspend";  icon: ""; cmd: "systemctl suspend" }
                ListElement { label: "Reboot";   icon: ""; cmd: "systemctl reboot" }
                ListElement { label: "Shutdown"; icon: ""; cmd: "systemctl poweroff" }
            }

            delegate: Rectangle {
                required property string label
                required property string icon
                required property string cmd
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
                    onClicked: {
                        console.log("power:", cmd)
                        powerProc.command = ["sh", "-c", cmd]
                        powerProc.startDetached()
                        root.actionTriggered()
                    }
                }
            }
        }
    }
}
