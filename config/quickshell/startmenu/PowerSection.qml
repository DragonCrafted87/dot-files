import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Rectangle {
    id: root
    radius: 8
    color: "#000000"
    border.color: "#555753"
    border.width: 1
    implicitHeight: 52

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
        anchors.margins: 6
        spacing: 6

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
                Layout.minimumWidth: Math.max(64, labelText.implicitWidth + 12)
                Layout.preferredWidth: Math.max(72, labelText.implicitWidth + 16)
                Layout.minimumHeight: 32
                radius: 6
                color: powerMouse.containsMouse ? "#555753" : "transparent"

                Text {
                    id: labelText
                    anchors.centerIn: parent
                    text: label
                    color: index === 4 ? "#EF2929" : "#D3D7CF"
                    font.pixelSize: 12
                    elide: Text.ElideNone
                    wrapMode: Text.NoWrap
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
