import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    // Pomodoro State
    property bool isRunning: false
    property int timeRemaining: 1500
    property string sessionType: "work" // "work", "short-break", "long-break"
    property string taskTitle: ""
    property string taskPath: ""
    property int plannedDuration: 25
    property int workDuration: 25
    property int shortBreakDuration: 5
    property int longBreakDuration: 10
    property var activePeriods: []
    property bool bridgeActive: false
    readonly property bool windowVisible: pomodoroWin.visible

    readonly property string timeRemainingFormatted: {
        const m = Math.floor(timeRemaining / 60);
        const s = timeRemaining % 60;
        return (m < 10 ? "0" + m : m) + ":" + (s < 10 ? "0" + s : s);
    }

    readonly property string sessionLabel: {
        if (sessionType === "short-break") return "Pausa Curta";
        if (sessionType === "long-break") return "Pausa Longa";
        return "Foco";
    }

    readonly property real progress: {
        const totalSec = plannedDuration > 0 ? plannedDuration * 60 : (sessionType === "work" ? workDuration * 60 : shortBreakDuration * 60);
        if (totalSec <= 0) return 0;
        return Math.max(0, Math.min(1.0, 1.0 - (timeRemaining / totalSec)));
    }

    // Local ticker to count down smoothly every second when running
    Timer {
        id: localTicker
        interval: 1000
        repeat: true
        running: root.isRunning
        onTriggered: {
            if (root.timeRemaining > 0) {
                root.timeRemaining--;
            } else {
                root.isRunning = false;
            }
        }
    }

    // Bridge state file view
    FileView {
        id: bridgeStateFile
        path: "/run/user/" + Quickshell.env("UID", "1000") + "/tasknotes-pomodoro.json"
        watchChanges: true
        onLoaded: root.parseBridgeState()
    }

    // Fallback data file from Obsidian plugin data.json (configured via plugin settings)
    FileView {
        id: fallbackDataFile
        path: {
            const custom = root.pluginData?.vaultPath;
            if (custom && custom.trim().length > 0) {
                return (custom.startsWith("~") ? custom.replace("~", Quickshell.env("HOME")) : custom) + "/.obsidian/plugins/tasknotes/data.json";
            }
            return "";
        }
        watchChanges: true
        onLoaded: {
            if (!root.bridgeActive) {
                root.parseFallbackState();
            }
        }
    }

    function parseBridgeState() {
        try {
            const raw = bridgeStateFile.text();
            if (!raw || !raw.trim()) return;
            const data = JSON.parse(raw);
            if (!data || typeof data !== "object") return;

            root.bridgeActive = true;
            root.isRunning = Boolean(data.isRunning);
            root.timeRemaining = typeof data.timeRemaining === "number" ? Math.max(0, data.timeRemaining) : 1500;
            root.sessionType = data.sessionType || "work";
            root.taskTitle = data.taskTitle || "";
            root.taskPath = data.taskPath || "";
            root.plannedDuration = data.plannedDuration || 25;
            root.workDuration = data.workDuration || 25;
            root.shortBreakDuration = data.shortBreakDuration || 5;
            root.longBreakDuration = data.longBreakDuration || 10;
            root.activePeriods = data.activePeriods || [];
        } catch (e) {
            console.warn("[TasknotesPomodoro] Error parsing bridge state:", e);
        }
    }

    function parseFallbackState() {
        try {
            const raw = fallbackDataFile.text();
            if (!raw || !raw.trim()) return;
            const data = JSON.parse(raw);
            if (!data) return;

            const pState = data.pomodoroState || {};
            root.isRunning = Boolean(pState.isRunning);
            root.timeRemaining = typeof pState.timeRemaining === "number" ? Math.max(0, pState.timeRemaining) : 1500;
            root.workDuration = data.pomodoroWorkDuration || 25;
            root.shortBreakDuration = data.pomodoroShortBreakDuration || 5;
            root.longBreakDuration = data.pomodoroLongBreakDuration || 10;

            const session = pState.currentSession;
            if (session) {
                root.sessionType = session.type || "work";
                root.plannedDuration = session.plannedDuration || 25;
                root.taskPath = session.taskPath || data.lastSelectedTaskPath || "";
                root.activePeriods = session.activePeriods || [];
            } else {
                root.sessionType = pState.nextSessionType || "work";
                root.plannedDuration = root.sessionType === "short-break" ? root.shortBreakDuration : (root.sessionType === "long-break" ? root.longBreakDuration : root.workDuration);
                root.taskPath = data.lastSelectedTaskPath || "";
            }

            if (root.taskPath) {
                const parts = root.taskPath.split("/");
                const fileName = parts[parts.length - 1].replace(/\.md$/i, "");
                root.taskTitle = fileName;
            }
        } catch (e) {
            console.warn("[TasknotesPomodoro] Error parsing fallback data.json:", e);
        }
    }

    // Helper to send commands to bridge without stealing focus
    function sendBridgeCommand(cmd, extra) {
        const uid = Quickshell.env("UID", "1000");
        const cmdFile = "/run/user/" + uid + "/tasknotes-pomodoro.cmd";
        const payload = JSON.stringify({ cmd: cmd, ...extra });
        Quickshell.execDetached(["bash", "-c", "echo '" + payload + "' > " + cmdFile]);
    }

    // Focus Obsidian window via Niri
    function focusObsidian() {
        Quickshell.execDetached(["bash", "-c", "obs_id=$(niri msg -j windows 2>/dev/null | jq -r '.[] | select(.app_id==\"md.Obsidian\") | .id' | head -n 1); [ -n \"$obs_id\" ] && niri msg action focus-window --id \"$obs_id\""]);
    }

    function toggleWindow() {
        pomodoroWin.visible = !pomodoroWin.visible;
    }

    function showWindow() {
        pomodoroWin.visible = true;
    }

    function hideWindow() {
        pomodoroWin.visible = false;
    }

    function togglePlayPause() {
        if (root.isRunning) {
            root.isRunning = false;
            sendBridgeCommand("pause");
        } else {
            root.isRunning = true;
            sendBridgeCommand("resume");
        }
    }

    function stop() {
        root.isRunning = false;
        root.timeRemaining = (root.sessionType === "short-break" ? root.shortBreakDuration : (root.sessionType === "long-break" ? root.longBreakDuration : root.workDuration)) * 60;
        sendBridgeCommand("stop");
    }

    function skipBreak() {
        sendBridgeCommand("skip-break");
    }

    function openActiveTask() {
        if (!root.taskPath) {
            openTaskSelector();
            return;
        }
        Quickshell.execDetached(["xdg-open", "obsidian://tasknotes-pomodoro?cmd=open-task&path=" + encodeURIComponent(root.taskPath)]);
        focusObsidian();
    }

    function openTaskSelector() {
        Quickshell.execDetached(["xdg-open", "obsidian://tasknotes-pomodoro?cmd=select-task"]);
        focusObsidian();
    }

    // IPC handler for keybinds or external scripts (dms ipc call tasknotesPomodoro <cmd>)
    IpcHandler {
        target: "tasknotesPomodoro"

        function toggle(): string {
            root.toggleWindow();
            return root.windowVisible ? "opened" : "collapsed";
        }

        function show(): string {
            root.showWindow();
            return "opened";
        }

        function hide(): string {
            root.hideWindow();
            return "collapsed";
        }

        function playPause(): string {
            root.togglePlayPause();
            return root.isRunning ? "running" : "paused";
        }

        function switchTask(): string {
            root.openTaskSelector();
            return "task-selector-opened";
        }

        function openTask(): string {
            root.openActiveTask();
            return "task-opened";
        }
    }

    // Floating Window Component
    FloatingWindow {
        id: pomodoroWin

        title: "Pomodoro - TaskNotes"
        minimumSize: Qt.size(260, 200)
        implicitWidth: 360
        implicitHeight: 280
        color: "transparent"
        visible: false

        onClosed: pomodoroWin.visible = false

        // Scale factor: scales all typography, icons, and spacing based on window size
        readonly property real scaleFactor: Math.max(0.75, Math.min(2.2, Math.min(width / 340, height / 260)))

        // Window background card (translucent frosted glass, Niri blurred)
        Rectangle {
            id: mainCard
            anchors.fill: parent
            anchors.margins: 6
            radius: Theme.cornerRadius
            color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.72)
            border.width: 1
            border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.22)
            clip: true

            ColumnLayout {
                anchors.fill: parent
                spacing: Math.round(Theme.spacingS * pomodoroWin.scaleFactor)

                // 1. Header / Titlebar (Draggable)
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.round(38 * Math.min(1.2, pomodoroWin.scaleFactor))

                    MouseArea {
                        anchors.fill: parent
                        onPressed: windowControls.tryStartMove()
                        onDoubleClicked: windowControls.tryToggleMaximize()
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: Theme.surfaceContainerHigh
                        opacity: 0.35
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingM
                        anchors.rightMargin: Theme.spacingS
                        spacing: Theme.spacingS

                        DankIcon {
                            name: root.sessionType === "work" ? "timer" : "coffee"
                            size: Math.round(Theme.iconSizeSmall * pomodoroWin.scaleFactor)
                            color: root.sessionType === "work" ? Theme.primary : Theme.secondary
                        }

                        StyledText {
                            text: "Pomodoro"
                            font.pixelSize: Math.round(Theme.fontSizeMedium * pomodoroWin.scaleFactor)
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                        }

                        // Session badge
                        Rectangle {
                            radius: Theme.cornerRadiusSmall
                            color: root.sessionType === "work"
                                ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.20)
                                : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.20)
                            implicitHeight: Math.round(20 * pomodoroWin.scaleFactor)
                            implicitWidth: badgeText.implicitWidth + Theme.spacingS * 2

                            StyledText {
                                id: badgeText
                                anchors.centerIn: parent
                                text: root.sessionLabel
                                font.pixelSize: Math.round(Theme.fontSizeSmall * 0.9 * pomodoroWin.scaleFactor)
                                font.weight: Font.DemiBold
                                color: root.sessionType === "work" ? Theme.primary : Theme.secondary
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Collapse button (collapses to DankBar)
                        DankActionButton {
                            circular: false
                            iconName: "close_fullscreen"
                            iconSize: Math.round(18 * pomodoroWin.scaleFactor)
                            iconColor: Theme.onSurfaceVariant
                            tooltipText: "Colapsar para a barra"
                            onClicked: pomodoroWin.visible = false
                        }

                        // Close button
                        DankActionButton {
                            circular: false
                            iconName: "close"
                            iconSize: Math.round(18 * pomodoroWin.scaleFactor)
                            iconColor: Theme.onSurfaceVariant
                            tooltipText: "Fechar"
                            onClicked: pomodoroWin.visible = false
                        }
                    }
                }

                // 2. Task Card (Clickable -> Opens note in Obsidian)
                Rectangle {
                    id: taskCard
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.round(48 * pomodoroWin.scaleFactor)
                    Layout.leftMargin: Theme.spacingM
                    Layout.rightMargin: Theme.spacingM
                    radius: Theme.cornerRadiusSmall
                    color: taskMouseArea.containsMouse
                        ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                        : Qt.rgba(Theme.surfaceContainerHigh.r, Theme.surfaceContainerHigh.g, Theme.surfaceContainerHigh.b, 0.45)
                    border.width: 1
                    border.color: taskMouseArea.containsMouse
                        ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.40)
                        : Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.15)

                    MouseArea {
                        id: taskMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openActiveTask()
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingM
                        anchors.rightMargin: Theme.spacingM
                        spacing: Theme.spacingS

                        DankIcon {
                            name: root.taskPath ? "task_alt" : "assignment"
                            size: Math.round(Theme.iconSize * pomodoroWin.scaleFactor)
                            color: root.taskPath ? Theme.primary : Theme.onSurfaceVariant
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            StyledText {
                                Layout.fillWidth: true
                                text: root.taskTitle ? root.taskTitle : "Nenhuma tarefa em execução"
                                font.pixelSize: Math.round(Theme.fontSizeMedium * pomodoroWin.scaleFactor)
                                font.weight: Font.Medium
                                color: root.taskTitle ? Theme.surfaceText : Theme.onSurfaceVariant
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }

                            StyledText {
                                text: root.taskPath ? "Clique para abrir no Obsidian" : "Clique para selecionar uma tarefa"
                                font.pixelSize: Math.round(Theme.fontSizeSmall * 0.85 * pomodoroWin.scaleFactor)
                                color: Theme.onSurfaceVariant
                                elide: Text.ElideRight
                            }
                        }

                        DankIcon {
                            name: "open_in_new"
                            size: Math.round(16 * pomodoroWin.scaleFactor)
                            color: Theme.onSurfaceVariant
                            opacity: taskMouseArea.containsMouse ? 1.0 : 0.4
                        }
                    }
                }

                // 3. Central Timer Display
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: Math.round(Theme.spacingXS * pomodoroWin.scaleFactor)

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.timeRemainingFormatted
                            font.pixelSize: Math.round(46 * pomodoroWin.scaleFactor)
                            font.bold: true
                            color: root.sessionType === "work" ? Theme.primary : Theme.secondary
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.isRunning ? "▶ Em andamento" : (root.timeRemaining > 0 ? "⏸ Pausado" : "Concluído")
                            font.pixelSize: Math.round(Theme.fontSizeSmall * pomodoroWin.scaleFactor)
                            color: root.isRunning ? Theme.primary : (root.timeRemaining > 0 ? Theme.warning : Theme.success)
                        }

                        // Progress bar
                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: Math.round(200 * pomodoroWin.scaleFactor)
                            Layout.preferredHeight: Math.max(4, Math.round(6 * pomodoroWin.scaleFactor))
                            radius: height / 2
                            color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.20)

                            Rectangle {
                                width: parent.width * root.progress
                                height: parent.height
                                radius: parent.radius
                                color: root.sessionType === "work" ? Theme.primary : Theme.secondary
                            }
                        }
                    }
                }

                // 4. Action Controls Bar
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.round(52 * pomodoroWin.scaleFactor)
                    Layout.leftMargin: Theme.spacingM
                    Layout.rightMargin: Theme.spacingM
                    Layout.bottomMargin: Theme.spacingS
                    radius: Theme.cornerRadiusSmall
                    color: Qt.rgba(Theme.surfaceContainerHigh.r, Theme.surfaceContainerHigh.g, Theme.surfaceContainerHigh.b, 0.35)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingS
                        anchors.rightMargin: Theme.spacingS
                        spacing: Theme.spacingS

                        // Trocar Tarefa (Opens Task Selector in Obsidian)
                        Rectangle {
                            id: switchTaskBtn
                            Layout.preferredHeight: Math.round(36 * pomodoroWin.scaleFactor)
                            Layout.preferredWidth: Math.round(130 * pomodoroWin.scaleFactor)
                            radius: Theme.cornerRadiusSmall
                            color: switchMouse.containsMouse
                                ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25)
                                : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                            border.width: 1
                            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)

                            MouseArea {
                                id: switchMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openTaskSelector()
                            }

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: Theme.spacingXS

                                DankIcon {
                                    name: "swap_horiz"
                                    size: Math.round(18 * pomodoroWin.scaleFactor)
                                    color: Theme.primary
                                }

                                StyledText {
                                    text: "Trocar Tarefa"
                                    font.pixelSize: Math.round(Theme.fontSizeSmall * pomodoroWin.scaleFactor)
                                    font.weight: Font.Medium
                                    color: Theme.primary
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Play / Pause Button
                        Rectangle {
                            id: playPauseBtn
                            Layout.preferredHeight: Math.round(36 * pomodoroWin.scaleFactor)
                            Layout.preferredWidth: Math.round(36 * pomodoroWin.scaleFactor)
                            radius: width / 2
                            color: playMouse.containsMouse
                                ? Qt.lighter(Theme.primary, 1.1)
                                : Theme.primary

                            MouseArea {
                                id: playMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.togglePlayPause()
                            }

                            DankIcon {
                                anchors.centerIn: parent
                                name: root.isRunning ? "pause" : "play_arrow"
                                size: Math.round(20 * pomodoroWin.scaleFactor)
                                color: Theme.onPrimary
                            }
                        }

                        // Stop Button
                        Rectangle {
                            id: stopBtn
                            Layout.preferredHeight: Math.round(36 * pomodoroWin.scaleFactor)
                            Layout.preferredWidth: Math.round(36 * pomodoroWin.scaleFactor)
                            radius: width / 2
                            color: stopMouse.containsMouse
                                ? Theme.surfaceContainerHighest
                                : Theme.surfaceContainerHigh

                            MouseArea {
                                id: stopMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.stop()
                            }

                            DankIcon {
                                anchors.centerIn: parent
                                name: "stop"
                                size: Math.round(18 * pomodoroWin.scaleFactor)
                                color: Theme.onSurfaceVariant
                            }
                        }

                        // Skip Break Button (if on break)
                        Rectangle {
                            visible: root.sessionType !== "work"
                            Layout.preferredHeight: Math.round(36 * pomodoroWin.scaleFactor)
                            Layout.preferredWidth: Math.round(36 * pomodoroWin.scaleFactor)
                            radius: width / 2
                            color: skipMouse.containsMouse
                                ? Theme.surfaceContainerHighest
                                : Theme.surfaceContainerHigh

                            MouseArea {
                                id: skipMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.skipBreak()
                            }

                            DankIcon {
                                anchors.centerIn: parent
                                name: "skip_next"
                                size: Math.round(18 * pomodoroWin.scaleFactor)
                                color: Theme.onSurfaceVariant
                            }
                        }
                    }
                }
            }
        }

        // Draggable edge/corner resize controls
        FloatingWindowControls {
            id: windowControls
            targetWindow: pomodoroWin
        }
    }
}
