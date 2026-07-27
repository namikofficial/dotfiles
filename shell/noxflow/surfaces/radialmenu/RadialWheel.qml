// RadialWheel — hold-to-open shortcut wheel.
// Stolen from: Monochrome OS radial interaction.
// 8 segments in a circle, app launches on release or click.
// Hold Super+Tab to open, release to launch the hovered slot.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../theme" as Theme
import "../../components" as Components

PanelWindow {
    id: root

    required property var noxd

    // ── Slot definitions ──
    property var slots: [
        { icon: "♫", label: "Music", action: "media_play_pause", actionParams: {} },
        { icon: "⌁", label: "Network", action: "network_refresh", actionParams: {} },
        { icon: "◈", label: "Bluetooth", action: "bluetooth_set_powered", actionParams: { powered: true } },
        { icon: "⚡", label: "Terminal", action: "launch", actionParams: { command: "kitty" } },
        { icon: "◉", label: "Files", action: "launch", actionParams: { command: "thunar" } },
        { icon: "◆", label: "Browser", action: "launch", actionParams: { command: "firefox" } },
        { icon: "☰", label: "Launcher", action: "toggle_launcher", actionParams: {} },
        { icon: "✕", label: "Close", action: "close_wheel", actionParams: {} }
    ]

    // ── State ──
    property real openProgress: 0
    property bool wheelOpen: false
    property int hoveredSlot: -1
    readonly property real outerR: Math.min(width, height) / 2 - Theme.Tokens.scaled(20)
    readonly property real innerR: Theme.Tokens.scaled(44)
    readonly property int slotCount: 8
    readonly property real cx: width / 2
    readonly property real cy: height / 2

    // ── Window ──
    implicitWidth: Theme.Tokens.scaled(420)
    implicitHeight: Theme.Tokens.scaled(420)
    exclusiveZone: 0
    aboveWindows: true
    focusable: true
    color: "transparent"
    visible: wheelOpen

    Behavior on openProgress {
        NumberAnimation { duration: Theme.Tokens.duration(200); easing.type: Easing.OutBack }
    }

    // ── Convert Qt color to CSS hex ──
    function hexColor(color) {
        var r = Math.max(0, Math.min(255, Math.round(color.r * 255)));
        var g = Math.max(0, Math.min(255, Math.round(color.g * 255)));
        var b = Math.max(0, Math.min(255, Math.round(color.b * 255)));
        return "#" + [r, g, b].map(c => c.toString(16).padStart(2, "0")).join("");
    }

    // ── Scrim ──
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Theme.Tokens.withAlpha(Theme.Tokens.surfaceSurfaceContainerHigh, 0.88 * root.openProgress)
        border.color: Theme.Tokens.outlineDefault
        border.width: 1
        scale: 0.5 + 0.5 * root.openProgress
        opacity: root.openProgress
        Behavior on scale { NumberAnimation { duration: Theme.Tokens.duration(200); easing.type: Easing.OutBack } }
        Behavior on opacity { NumberAnimation { duration: Theme.Tokens.duration(150) } }
    }

    // ── Canvas wheel ──
    Canvas {
        id: wheelCanvas
        anchors.fill: parent
        opacity: root.openProgress

        onPaint: {
            var ctx = getContext("2d");
            var w = width;
            var h = height;
            ctx.clearRect(0, 0, w, h);

            var outer = root.outerR;
            var inner = root.innerR;
            var seg = 2 * Math.PI / root.slotCount;

            for (var i = 0; i < root.slotCount; i++) {
                var a0 = -Math.PI / 2 + i * seg - seg / 2;
                var a1 = a0 + seg;

                // Fill segment
                ctx.beginPath();
                ctx.arc(root.cx, root.cy, outer, a0, a1);
                ctx.arc(root.cx, root.cy, inner, a1, a0, true);
                ctx.closePath();

                if (i === root.hoveredSlot) {
                    ctx.fillStyle = hexColor(Theme.Tokens.tonalPrimaryContainer);
                    ctx.globalAlpha = 0.9;
                    ctx.fill();
                    ctx.globalAlpha = 1;
                    ctx.strokeStyle = hexColor(Theme.Tokens.tonalPrimary);
                    ctx.lineWidth = 2;
                    ctx.stroke();
                } else {
                    ctx.fillStyle = hexColor(Theme.Tokens.surfaceSurfaceContainer);
                    ctx.globalAlpha = 0.6;
                    ctx.fill();
                    ctx.globalAlpha = 1;
                }

                // Separator line
                var sa = -Math.PI / 2 + i * seg;
                ctx.beginPath();
                ctx.moveTo(root.cx + inner * Math.cos(sa), root.cy + inner * Math.sin(sa));
                ctx.lineTo(root.cx + outer * Math.cos(sa), root.cy + outer * Math.sin(sa));
                ctx.strokeStyle = hexColor(Theme.Tokens.outlineSubtle);
                ctx.lineWidth = 1;
                ctx.stroke();
            }

            // Inner hub
            ctx.beginPath();
            ctx.arc(root.cx, root.cy, inner, 0, 2 * Math.PI);
            ctx.fillStyle = hexColor(Theme.Tokens.surfaceSurfaceContainer);
            ctx.globalAlpha = 0.85;
            ctx.fill();
            ctx.globalAlpha = 1;
            ctx.strokeStyle = hexColor(Theme.Tokens.outlineDefault);
            ctx.lineWidth = 1;
            ctx.stroke();
        }

        Connections {
            target: root
            function onHoveredSlotChanged() { wheelCanvas.requestPaint() }
        }
        Component.onCompleted: wheelCanvas.requestPaint()
    }

    // ── Slot icons+labels (positioned at segment midpoints) ──
    Repeater {
        model: root.slots
        delegate: Item {
            required property int index
            required property var modelData

            readonly property real angle: -Math.PI / 2 + (index + 0.5) * 2 * Math.PI / root.slotCount
            readonly property real itemR: (root.outerR + root.innerR) / 2

            x: root.cx + itemR * Math.cos(angle) - width / 2
            y: root.cy + itemR * Math.sin(angle) - height / 2
            width: Theme.Tokens.scaled(56)
            height: Theme.Tokens.scaled(60)
            opacity: root.openProgress

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 2
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: modelData.icon || "?"
                    color: index === root.hoveredSlot ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textPrimary
                    font.pixelSize: Theme.Tokens.iconMd
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: modelData.label || ""
                    color: index === root.hoveredSlot ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textSecondary
                    font.pixelSize: Theme.Tokens.typographyLabelSmall
                    maximumLineCount: 1
                }
            }
        }
    }

    // ── Center label ──
    Text {
        anchors.centerIn: parent
        text: root.hoveredSlot >= 0 ? root.slots[root.hoveredSlot].label || "" : "⏎"
        color: root.hoveredSlot >= 0 ? Theme.Tokens.tonalPrimary : Theme.Tokens.textMuted
        font.pixelSize: root.hoveredSlot >= 0 ? Theme.Tokens.typographyTitleMedium : Theme.Tokens.iconLg
        font.bold: root.hoveredSlot >= 0
        opacity: root.openProgress
        z: 10
    }

    // ── Mouse tracking ──
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true

        onPositionChanged: function(mouse) {
            var dx = mouse.x - root.cx;
            var dy = mouse.y - root.cy;
            var dist = Math.sqrt(dx * dx + dy * dy);

            if (dist < root.innerR || dist > root.outerR) {
                root.hoveredSlot = -1;
                return;
            }

            // Angle from 12 o'clock clockwise
            var angle = Math.atan2(dy, dx) + Math.PI / 2;
            if (angle < 0) angle += 2 * Math.PI;

            root.hoveredSlot = Math.floor(angle / (2 * Math.PI / root.slotCount));
        }

        onExited: root.hoveredSlot = -1
        onClicked: root.hoveredSlot >= 0 ? root.activateSlot(root.hoveredSlot) : root.close()
    }

    // ── Keyboard ──
    Item {
        anchors.fill: parent
        focus: true

        Keys.onLeftPressed: root.navigateSlot(-1)
        Keys.onRightPressed: root.navigateSlot(1)
        Keys.onUpPressed: root.navigateSlot(-2)
        Keys.onDownPressed: root.navigateSlot(2)
        Keys.onReturnPressed: { if (root.hoveredSlot >= 0) root.activateSlot(root.hoveredSlot); else root.close() }
        Keys.onEscapePressed: root.close()
        Keys.onSpacePressed: { if (root.hoveredSlot >= 0) root.activateSlot(root.hoveredSlot); }
    }

    function navigateSlot(delta) {
        if (root.hoveredSlot < 0) root.hoveredSlot = 0;
        else root.hoveredSlot = (root.hoveredSlot + delta + root.slotCount) % root.slotCount;
    }

    // ── Actions ──
    function activateSlot(index) {
        if (index < 0 || index >= slots.length) return;
        var slot = slots[index];
        if (!slot || !slot.action) return;

        switch (slot.action) {
            case "close_wheel": root.close(); break;
            case "toggle_launcher":
                root.close();
                if (root.noxd && root.noxd.connected) root.noxd.runAction({ toggle_launcher: {} });
                break;
            case "launch":
                if (slot.actionParams && slot.actionParams.command) Quickshell.exec(slot.actionParams.command);
                root.close();
                break;
            default:
                if (root.noxd && root.noxd.connected) {
                    var action = {};
                    action[slot.action] = slot.actionParams || {};
                    root.noxd.runAction(action);
                }
                root.close();
                break;
        }
    }

    // ── Public API ──
    function open() {
        wheelOpen = true;
        openProgress = 1;
        hoveredSlot = -1;
        forceActiveFocus();
        wheelCanvas.requestPaint();
    }

    function close() {
        closeAnim.start();
    }

    SequentialAnimation {
        id: closeAnim
        NumberAnimation { target: root; property: "openProgress"; from: 1; to: 0; duration: 150; easing.type: Easing.InCubic }
        onFinished: root.wheelOpen = false
    }

    function toggle() { if (wheelOpen) close(); else open(); }

    // ── Config loading ──
    function loadConfig(configSlots) {
        if (Array.isArray(configSlots) && configSlots.length > 0) slots = configSlots;
    }
}
