//@ pragma UseQApplication
//@ pragma ShellId volume-osd
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import Quickshell.Widgets

ShellRoot {
    id: root

    property bool shouldShow: false
    property real volume: 0
    property bool muted: false
    readonly property bool overDrive: volume > 1 && !muted

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    function readSink() {
        const a = Pipewire.defaultAudioSink?.audio
        if (!a) {
            root.volume = 0
            root.muted = true
            return
        }
        const v = a.volume
        root.volume = (typeof v === "number" && isFinite(v)) ? Math.max(0, v) : 0
        root.muted = !!a.muted
    }

    Connections {
        target: Pipewire.defaultAudioSink?.audio ?? null
        function onVolumeChanged() {
            root.readSink()
            root.shouldShow = true
            hideTimer.restart()
        }
        function onMutedChanged() {
            root.readSink()
            root.shouldShow = true
            hideTimer.restart()
        }
    }

    Timer {
        id: hideTimer
        interval: 1800
        onTriggered: root.shouldShow = false
    }

    LazyLoader {
        active: root.shouldShow

        PanelWindow {
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "qs-volume-osd"
            color: "transparent"
            mask: Region {}

            anchors {
                top: true
                right: true
            }
            margins {
                top: 24
                right: 24
            }

            implicitWidth: 44
            implicitHeight: 220

            Rectangle {
                anchors.fill: parent
                radius: 14
                color: "#e61e1e2e"
                border.color: root.overDrive ? "#f38ba8" : "#45475a"
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.muted ? "MUTE" : Math.round(root.volume * 100) + "%"
                        color: root.overDrive ? "#f38ba8" : "#cdd6f4"
                        font.pixelSize: 11
                        font.bold: root.overDrive
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 8
                        color: "#11111b"

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: {
                                const shown = root.muted ? 0 : Math.min(root.volume, 1.5)
                                return parent.height * (shown / 1.5)
                            }
                            radius: 8
                            color: root.overDrive ? "#f38ba8" : (root.muted ? "#45475a" : "#89b4fa")
                        }
                    }
                }
            }
        }
    }
}
