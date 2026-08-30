// NotificationItem — single notification card with Rivendell-style
// falling-knight physics (FrameAnimation spring-damper).
// Pop-in from 200px offset + 45° rotation → springs to rest.
// Fling-to-dismiss with gravity on swipe.
// Stolen from: zacoons/rivendell-hyprdots (physics engine) + DMS + Tide.

import QtQuick
import QtQuick.Layouts
import "../theme" as Theme

FocusScope {
    id: root

    required property var notification
    property bool hovered: false

    signal dismissed(var notification)
    signal actionInvoked(var notification, string actionId)

    implicitWidth: parent ? parent.width : Theme.Tokens.scaled(360)
    implicitHeight: layout.height + Theme.Tokens.scaled(Theme.Tokens.spacingSm * 2)

    activeFocusOnTab: true

    Accessible.role: Accessible.Notification
    Accessible.name: notification.summary + " " + notification.body
    Accessible.description: "Notification from " + notification.app_name

    // ── Physics state (Rivendell-style FrameAnimation spring-damper) ──
    enum AnimState { Returning, Inert, Flinging, Dismissing }

    property int animState: NotificationItem.Returning
    property real physicsX: 0.0        // offset from rest position
    property real physicsY: -200.0     // starts above viewport
    property real physicsRot: 45.0     // starts rotated
    property real velocityX: 0.0
    property real velocityY: 0.0
    property real velocityRot: 0.0
    property real targetX: 0.0
    property real targetY: 0.0
    property real targetRot: 0.0
    property real gravity: 3000.0      // pixels/s² for fling

    // Spring-damper constants (Rivendell values)
    readonly property real springK: 1.0
    readonly property real damping: 0.1

    // Track touch/mouse for fling detection
    property real dragStartX: 0
    property real dragStartY: 0
    property real lastDragX: 0
    property real lastDragTime: 0
    property bool dragging: false

    // ── Per-frame physics loop ──
    FrameAnimation {
        id: physicsLoop
        running: root.animState !== NotificationItem.Inert
        onTriggered: function(delta) {
            var dt = Math.min(delta, 0.05); // cap to 50ms to avoid explosion
            var frameTime = dt / 1000.0;      // convert ms → seconds

            switch (root.animState) {
            case NotificationItem.Returning:
                // Spring-damper toward target
                var dx = root.targetX - root.physicsX;
                var dy = root.targetY - root.physicsY;
                var drot = root.targetRot - root.physicsRot;

                var springForceX = root.springK * dx;
                var springForceY = root.springK * dy;
                var springForceRot = root.springK * drot;

                var dampingForceX = -root.damping * root.velocityX;
                var dampingForceY = -root.damping * root.velocityY;
                var dampingForceRot = -root.damping * root.velocityRot;

                root.velocityX += (springForceX + dampingForceX) * 60 * frameTime;
                root.velocityY += (springForceY + dampingForceY) * 60 * frameTime;
                root.velocityRot += (springForceRot + dampingForceRot) * 60 * frameTime;

                root.physicsX += root.velocityX * frameTime;
                root.physicsY += root.velocityY * frameTime;
                root.physicsRot += root.velocityRot * frameTime;

                // Settled check
                if (Math.abs(root.velocityX) < 1 && Math.abs(root.velocityY) < 1
                        && Math.abs(root.physicsX) < 0.5 && Math.abs(root.physicsY) < 0.5
                        && Math.abs(root.velocityRot) < 1 && Math.abs(root.physicsRot) < 0.5) {
                    root.velocityX = 0; root.velocityY = 0; root.velocityRot = 0;
                    root.physicsX = 0; root.physicsY = 0; root.physicsRot = 0;
                    root.animState = NotificationItem.Inert;
                }
                break;

            case NotificationItem.Flinging:
                // Gravity + drag
                root.velocityY += root.gravity * frameTime;
                root.velocityX *= 0.98; // air resistance
                root.velocityY *= 0.98;
                root.velocityRot *= 0.95;

                root.physicsX += root.velocityX * frameTime;
                root.physicsY += root.velocityY * frameTime;
                root.physicsRot = root.velocityX * 0.2; // rotation follows horizontal velocity

                // Off-screen → dismiss
                if (root.physicsY > 600 || Math.abs(root.physicsX) > 500) {
                    root.animState = NotificationItem.Dismissing;
                }
                break;

            case NotificationItem.Dismissing:
                // Accelerate off-screen right
                root.velocityX += 20000 * frameTime;
                root.physicsX += root.velocityX * frameTime;
                if (Math.abs(root.physicsX) > 800) {
                    physicsLoop.running = false;
                    root.dismissed(root.notification);
                }
                break;
            }
        }
    }

    // ── Drag handling for fling-to-dismiss ──
    DragHandler {
        id: dragHandler
        target: null  // manual tracking
        onActiveChanged: {
            if (dragHandler.active) {
                root.dragging = true;
                root.lastDragX = dragHandler.centroid.position.x;
                root.lastDragTime = Date.now();
                if (root.animState === NotificationItem.Inert) {
                    root.animState = NotificationItem.Returning;
                    root.targetX = 0; root.targetY = 0; root.targetRot = 0;
                }
            } else {
                root.dragging = false;
                var dragDist = dragStartX - dragHandler.centroid.position.x;
                var dragTime = Date.now() - root.lastDragTime;
                if (Math.abs(dragDist) > 80 || (dragTime < 200 && Math.abs(dragDist) > 30)) {
                    // Fling dismiss
                    root.animState = NotificationItem.Flinging;
                    root.velocityX = -dragDist / Math.max(dragTime, 50) * 1000;
                    root.velocityY = (dragHandler.centroid.position.y - dragStartY) / Math.max(dragTime, 50) * 1000;
                } else {
                    // Snap back
                    root.targetX = 0; root.targetY = 0; root.targetRot = 0;
                }
            }
            root.dragStartX = dragHandler.centroid.position.x;
            root.dragStartY = dragHandler.centroid.position.y;
        }
        onTranslationChanged: {
            var tx = dragHandler.centroid.position.x - dragStartX;
            var ty = dragHandler.centroid.position.y - dragStartY;
            root.physicsX = tx;
            root.physicsY = ty;
            root.velocityX = (tx - lastDragX) / Math.max(Date.now() - lastDragTime, 16) * 16;
            root.lastDragX = tx;
            root.lastDragTime = Date.now();
        }
    }

    // ── Startup animation trigger ──
    Component.onCompleted: {
        root.animState = NotificationItem.Returning;
        root.physicsY = -200;
        root.physicsRot = 45;
        physicsLoop.running = true;
    }

    // ── Render with physics transform ──
    transform: [
        Translate { x: root.physicsX },
        Translate { y: root.physicsY },
        Rotation { angle: root.physicsRot }
    ]

    // Transparency during dismiss — only when flying away
    opacity: root.animState === NotificationItem.Dismissing || root.animState === NotificationItem.Flinging
            ? Math.max(0, 1 - Math.abs(root.physicsX) / 300) : 1.0

    // ── Urgency border ──
    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 3
        radius: 2
        color: notification.urgency === "critical" ? Theme.Tokens.stateDanger
             : notification.urgency === "low" ? Theme.Tokens.stateInfo
             : Theme.Tokens.tonalPrimary
    }

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: 3
        radius: Theme.Tokens.radiusMd
        color: root.hovered ? Theme.Tokens.surfaceSurfaceContainerHighest
                           : Theme.Tokens.surfaceSurfaceContainer
        border.color: root.activeFocus ? Theme.Tokens.outlineFocus : Theme.Tokens.outlineSubtle
        border.width: root.activeFocus ? 2 : 1

        ColumnLayout {
            id: layout
            anchors.fill: parent
            anchors.margins: Theme.Tokens.spacingMd
            spacing: Theme.Tokens.spacingSm

            // Header: app icon + name + close
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.Tokens.spacingSm

                Text {
                    text: notification.app_icon || "◈"
                    color: Theme.Tokens.tonalPrimary
                    font.pixelSize: Theme.Tokens.iconSm
                }

                Text {
                    text: notification.app_name || "System"
                    color: Theme.Tokens.textSecondary
                    font.family: Theme.Tokens.typographyFontFamily
                    font.pixelSize: Theme.Tokens.typographyLabelSmall
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                Text {
                    text: notification.timestamp || ""
                    color: Theme.Tokens.textMuted
                    font.pixelSize: Theme.Tokens.typographyLabelSmall
                }

                Text {
                    text: "✕"
                    color: Theme.Tokens.textMuted
                    font.pixelSize: Theme.Tokens.iconSm
                    TapHandler { onTapped: { root.animState = NotificationItem.Dismissing; } }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                }
            }

            // Summary
            Text {
                text: notification.summary || ""
                color: Theme.Tokens.textPrimary
                font.family: Theme.Tokens.typographyFontFamily
                font.pixelSize: Theme.Tokens.typographyBodyMedium
                font.bold: true
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                visible: text !== ""
            }

            // Body
            Text {
                text: notification.body || ""
                color: Theme.Tokens.textSecondary
                font.family: Theme.Tokens.typographyFontFamily
                font.pixelSize: Theme.Tokens.typographyBodySmall
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                visible: text !== ""
                maximumLineCount: 3
                elide: Text.ElideRight
            }

            // Inline action buttons
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.Tokens.spacingXs
                visible: notification.actions && notification.actions.length > 0

                Repeater {
                    model: notification.actions
                    delegate: Rectangle {
                        required property var modelData
                        height: Theme.Tokens.scaled(Theme.Tokens.heightChip)
                        implicitWidth: actionLabel.width + Theme.Tokens.scaled(Theme.Tokens.spacingLg)
                        radius: Theme.Tokens.radiusPill
                        color: Theme.Tokens.surfaceSurfaceVariant

                        Text {
                            id: actionLabel
                            anchors.centerIn: parent
                            text: typeof modelData === "string" ? modelData : modelData.label || modelData.id || modelData
                            color: Theme.Tokens.textPrimary
                            font.pixelSize: Theme.Tokens.typographyLabelSmall
                        }

                        TapHandler {
                            onTapped: root.actionInvoked(root.notification,
                                typeof modelData === "string" ? modelData : modelData.id || modelData)
                        }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                    }
                }
                Item { Layout.fillWidth: true }
            }
        }
    }

    HoverHandler { onHoveredChanged: root.hovered = hovered }

    Keys.onDeletePressed: { root.animState = NotificationItem.Dismissing; }
    Keys.onEscapePressed: { root.animState = NotificationItem.Dismissing; }
}
