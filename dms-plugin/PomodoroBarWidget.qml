import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    readonly property var daemon: PluginService.pluginDaemonInstances["tasknotesPomodoro"]

    horizontalBarPill: Component {
        StyledRect {
            id: pill
            height: parent.widgetThickness
            width: pillRow.implicitWidth + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: mouseArea.containsMouse
                ? Theme.surfaceContainerHighest
                : (daemon?.windowVisible ? Theme.surfaceContainerHigh : Theme.surfaceContainer)

            border.width: 1
            border.color: daemon?.isRunning
                ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.45)
                : Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.15)

            MouseArea {
                id: mouseArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor

                onClicked: mouse => {
                    if (mouse.button === Qt.LeftButton) {
                        daemon?.toggleWindow();
                    } else if (mouse.button === Qt.RightButton) {
                        daemon?.togglePlayPause();
                    }
                }
            }

            Row {
                id: pillRow
                anchors.centerIn: parent
                spacing: Theme.spacingS

                DankIcon {
                    name: daemon?.sessionType === "work" ? "timer" : "coffee"
                    size: root.iconSize
                    color: daemon?.isRunning
                        ? Theme.primary
                        : (daemon?.timeRemaining > 0 ? Theme.warning : Theme.onSurfaceVariant)
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: daemon?.timeRemainingFormatted ?? "--:--"
                    color: daemon?.isRunning ? Theme.primary : Theme.surfaceText
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: daemon?.isRunning ? Font.Bold : Font.Normal
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    visible: (root.pluginData.showTaskTitleOnBar ?? true) && !!daemon?.taskTitle && root.barThickness > 32
                    text: daemon?.taskTitle ?? ""
                    color: Theme.onSurfaceVariant
                    font.pixelSize: Theme.fontSizeSmall
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    width: Math.min(110, implicitWidth)
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    verticalBarPill: Component {
        StyledRect {
            width: parent.widgetThickness
            height: vRow.implicitHeight + Theme.spacingS * 2
            radius: Theme.cornerRadius
            color: vMouseArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainer
            border.width: 1
            border.color: daemon?.isRunning ? Theme.primary : Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.15)

            MouseArea {
                id: vMouseArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => {
                    if (mouse.button === Qt.LeftButton) daemon?.toggleWindow();
                    else if (mouse.button === Qt.RightButton) daemon?.togglePlayPause();
                }
            }

            Column {
                id: vRow
                anchors.centerIn: parent
                spacing: Theme.spacingXS

                DankIcon {
                    name: daemon?.sessionType === "work" ? "timer" : "coffee"
                    size: root.iconSize
                    color: daemon?.isRunning ? Theme.primary : Theme.onSurfaceVariant
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    text: daemon?.timeRemainingFormatted ?? "--:--"
                    color: daemon?.isRunning ? Theme.primary : Theme.surfaceText
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: daemon?.isRunning ? Font.Bold : Font.Normal
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }
}
