import QtQuick
import "../theme" as Theme

Item {
    id: root
    property int size: Theme.Tokens.scaled(Theme.Tokens.iconMd)
    implicitWidth: size
    implicitHeight: size
    Rectangle { anchors.centerIn: parent; width: root.size * 0.7; height: root.size * 0.7; radius: width / 2; color: "transparent"; border.color: Theme.Tokens.tonalPrimary; border.width: 3; RotationAnimation on rotation { from: 0; to: 360; duration: Theme.Tokens.durationMedium; loops: Animation.Infinite; running: !Theme.Tokens.reducedMotion } }
    Rectangle { anchors.centerIn: parent; width: 4; height: 4; radius: 2; color: Theme.Tokens.tonalPrimary }
}
