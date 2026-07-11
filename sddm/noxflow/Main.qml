import QtQuick 2.0
import QtQuick.Window 2.0
import SddmComponents 2.0

Rectangle {
    id: root
    width: Screen.width
    height: Screen.height
    color: "#080b12"

    LayoutMirroring.enabled: Qt.locale().textDirection == Qt.RightToLeft
    LayoutMirroring.childrenInherit: true

    property color accent: "#00e5ff"
    property color accentSoft: "#2b00e5ff"
    property color panelBg: "#dc080b12"
    property color panelBgAlt: "#e0111522"
    property color panelBorder: "#6600e5ff"
    property color panelBorderSoft: "#2bffffff"
    property color textPrimary: "#edf7ff"
    property color textMuted: "#9aa9bd"
    property color okColor: "#59ffa1"
    property color badColor: "#ff3c78"
    property string statusMessage: textConstants.prompt
    property color statusColor: textMuted
    property bool compactLayout: width < 1080 || height < 780
    property int outerMargin: Math.max(24, Math.round(Math.min(width, height) * 0.04))
    property int shellWidth: Math.max(0, Math.min(width - outerMargin * 2, 1160))
    property int heroWidth: compactLayout ? shellWidth : 420
    property int authWidth: compactLayout ? shellWidth : 612
    property int topInset: compactLayout ? 16 : 20
    property int contentGap: compactLayout ? 18 : 24
    property int fieldHeight: compactLayout ? 46 : 48
    property int buttonHeight: compactLayout ? 42 : 44
    property bool screenReady: false

    TextConstants { id: textConstants }

    function submitLogin() {
        sddm.login(userEntry.text, passwordEntry.text, sessionBox.index)
    }

    Connections {
        target: sddm
        onLoginSucceeded: {
            statusMessage = textConstants.loginSucceeded
            statusColor = okColor
        }
        onLoginFailed: {
            passwordEntry.text = ""
            statusMessage = textConstants.loginFailed
            statusColor = badColor
        }
        onInformationMessage: {
            statusMessage = message
            statusColor = badColor
        }
    }

    Background {
        anchors.fill: parent
        source: config.background
        fillMode: Image.PreserveAspectCrop
        onStatusChanged: {
            if (status == Image.Error && source !== config.defaultBackground) {
                source = config.defaultBackground
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#6b05070c" }
            GradientStop { position: 0.55; color: "#92090d16" }
            GradientStop { position: 1.0; color: "#da0b0f18" }
        }
    }

    Rectangle {
        width: Math.round(root.width * 0.64)
        height: Math.round(root.height * 0.64)
        x: -width * 0.18
        y: -height * 0.16
        radius: width
        opacity: 0.24
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#3300e5ff" }
            GradientStop { position: 0.55; color: "#1400e5ff" }
            GradientStop { position: 1.0; color: "#00000000" }
        }
    }

    Rectangle {
        width: Math.round(root.width * 0.55)
        height: Math.round(root.height * 0.55)
        x: root.width - width * 0.82
        y: root.height - height * 0.78
        radius: width
        opacity: 0.2
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#44ff3cac" }
            GradientStop { position: 0.45; color: "#18ff3cac" }
            GradientStop { position: 1.0; color: "#00000000" }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#6f0b1020"
    }

    Rectangle {
        id: topBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: topBarFlow.implicitHeight + topInset * 2
        color: "#b7121724"
        border.color: "#223d5df7"
        border.width: 1
        opacity: 0.0
        scale: 0.995
        clip: true

        Behavior on opacity { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

        Flow {
            id: topBarFlow
            anchors.fill: parent
            anchors.leftMargin: outerMargin
            anchors.rightMargin: outerMargin
            anchors.topMargin: topInset
            anchors.bottomMargin: topInset
            spacing: contentGap

            Item {
                width: compactLayout ? topBarFlow.width : 360
                height: dateColumn.implicitHeight

                Column {
                    id: dateColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: 4

                    Text {
                        id: topDate
                        width: parent.width
                        color: textPrimary
                        font.pixelSize: compactLayout ? 15 : 16
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: sddm.hostName
                        color: textMuted
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                }
            }

            Flow {
                id: topControls
                width: compactLayout ? topBarFlow.width : 560
                spacing: 10

                Item {
                    width: compactLayout ? topControls.width : 120
                    height: controlLabel.implicitHeight + sessionBox.height + 4

                    Column {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        spacing: 4

                        Text {
                            id: controlLabel
                            text: textConstants.session
                            color: textMuted
                            font.pixelSize: 12
                            font.bold: true
                        }

                        ComboBox {
                            id: sessionBox
                            width: parent.width
                            height: 36
                            arrowIcon: "angle-down.png"
                            model: sessionModel
                            index: sessionModel.lastIndex
                            font.pixelSize: 13
                            KeyNavigation.backtab: powerButton
                            KeyNavigation.tab: layoutBox
                        }
                    }
                }

                Item {
                    width: compactLayout ? topControls.width : 120
                    height: layoutLabel.implicitHeight + layoutBox.height + 4

                    Column {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        spacing: 4

                        Text {
                            id: layoutLabel
                            text: textConstants.layout
                            color: textMuted
                            font.pixelSize: 12
                            font.bold: true
                        }

                        LayoutBox {
                            id: layoutBox
                            width: parent.width
                            height: 36
                            arrowIcon: "angle-down.png"
                            font.pixelSize: 13
                            KeyNavigation.backtab: sessionBox
                            KeyNavigation.tab: userEntry
                        }
                    }
                }
            }
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            topDate.text = Qt.formatDateTime(new Date(), "dddd, dd MMM yyyy  HH:mm")
            heroDate.text = Qt.formatDateTime(new Date(), "dddd, dd MMMM")
        }
    }

    Item {
        id: contentDock
        width: shellWidth
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: compactLayout ? 34 : 24
        opacity: 0.0
        scale: 0.985

        Behavior on opacity { NumberAnimation { duration: 360; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 360; easing.type: Easing.OutCubic } }

        Flow {
            id: contentFlow
            width: parent.width
            spacing: contentGap

            Rectangle {
                id: heroCard
                width: compactLayout ? contentFlow.width : heroWidth
                height: heroColumn.implicitHeight + 2 * heroPad
                radius: 22
                color: panelBg
                border.width: 1
                border.color: panelBorderSoft
                clip: true

                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#c0181d2d" }
                    GradientStop { position: 1.0; color: "#aa101625" }
                }

                property int heroPad: compactLayout ? 24 : 28

                Rectangle {
                    width: 5
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    color: accent
                    opacity: 0.9
                }

                Column {
                    id: heroColumn
                    anchors.fill: parent
                    anchors.margins: heroCard.heroPad
                    spacing: 14

                    Rectangle {
                        width: 86
                        height: 28
                        radius: 14
                        color: "#1f7aa2f7"
                        border.width: 1
                        border.color: "#337aa2f7"

                        Text {
                            anchors.centerIn: parent
                            text: "Noxflow"
                            color: textPrimary
                            font.pixelSize: 12
                            font.bold: true
                        }
                    }

                    Text {
                        text: sddm.hostName
                        color: accent
                        width: parent.width
                        font.pixelSize: compactLayout ? 30 : 36
                        font.bold: true
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        id: heroDate
                        width: parent.width
                        color: textMuted
                        font.pixelSize: 14
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        width: parent.width
                        text: "A calmer login surface with clearer hierarchy, tighter spacing, and enough motion to feel alive without getting in the way."
                        color: textPrimary
                        font.pixelSize: 15
                        wrapMode: Text.WordWrap
                        lineHeightMode: Text.FixedHeight
                        lineHeight: 22
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: "#22ffffff"
                    }

                    Text {
                        width: parent.width
                        text: "Pick your session, enter your credentials, and continue."
                        color: textMuted
                        font.pixelSize: 13
                        wrapMode: Text.WordWrap
                    }
                }
            }

            Rectangle {
                id: authCard
                width: compactLayout ? contentFlow.width : authWidth
                height: authColumn.implicitHeight + 2 * authPad
                radius: 22
                color: panelBgAlt
                border.width: 1
                border.color: panelBorder
                clip: true

                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#d01b2234" }
                    GradientStop { position: 1.0; color: "#c0121726" }
                }

                property int authPad: compactLayout ? 24 : 28

                Column {
                    id: authColumn
                    anchors.fill: parent
                    anchors.margins: authCard.authPad
                    spacing: 14

                    Column {
                        width: parent.width
                        spacing: 4

                        Text {
                            text: textConstants.userName
                            color: textPrimary
                            font.pixelSize: 22
                            font.bold: true
                        }

                        Text {
                            width: parent.width
                            text: "Enter the account password for this machine."
                            color: textMuted
                            font.pixelSize: 13
                            wrapMode: Text.WordWrap
                        }
                    }

                    Item {
                        width: parent.width
                        height: fieldHeight

                        Image {
                            source: "images/user_icon.png"
                            width: compactLayout ? 28 : 32
                            height: compactLayout ? 28 : 32
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        TextBox {
                            id: userEntry
                            anchors.left: parent.left
                            anchors.leftMargin: compactLayout ? 42 : 48
                            width: Math.max(0, parent.width - anchors.leftMargin)
                            height: parent.height
                            text: userModel.lastUser || ""
                            font.pixelSize: 16
                            KeyNavigation.backtab: layoutBox
                            KeyNavigation.tab: passwordEntry
                            Keys.onPressed: {
                                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    submitLogin()
                                    event.accepted = true
                                }
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        height: fieldHeight

                        Image {
                            source: "images/lock.png"
                            width: compactLayout ? 28 : 32
                            height: compactLayout ? 28 : 32
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        PasswordBox {
                            id: passwordEntry
                            anchors.left: parent.left
                            anchors.leftMargin: compactLayout ? 42 : 48
                            width: Math.max(0, parent.width - anchors.leftMargin)
                            height: parent.height
                            font.pixelSize: 16
                            tooltipBG: accent
                            KeyNavigation.backtab: userEntry
                            KeyNavigation.tab: loginButton
                            Keys.onPressed: {
                                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    submitLogin()
                                    event.accepted = true
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: "#22ffffff"
                    }

                    Text {
                        id: statusText
                        width: parent.width
                        text: statusMessage
                        color: statusColor
                        font.pixelSize: 13
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                    }

                    Flow {
                        id: actionsFlow
                        width: parent.width
                        spacing: 10

                        Button {
                            id: loginButton
                            text: textConstants.login
                            width: compactLayout ? actionsFlow.width : 174
                            height: buttonHeight
                            onClicked: submitLogin()
                            KeyNavigation.backtab: passwordEntry
                            KeyNavigation.tab: rebootButton
                        }

                        Button {
                            id: rebootButton
                            text: textConstants.reboot
                            width: compactLayout ? actionsFlow.width : 118
                            height: buttonHeight
                            onClicked: sddm.reboot()
                            KeyNavigation.backtab: loginButton
                            KeyNavigation.tab: powerButton
                        }

                        Button {
                            id: powerButton
                            text: textConstants.shutdown
                            width: compactLayout ? actionsFlow.width : 118
                            height: buttonHeight
                            onClicked: sddm.powerOff()
                            KeyNavigation.backtab: rebootButton
                            KeyNavigation.tab: suspendButton
                        }

                        Button {
                            id: suspendButton
                            text: "Suspend"
                            width: compactLayout ? actionsFlow.width : 118
                            height: buttonHeight
                            visible: sddm.canSuspend
                            onClicked: sddm.suspend()
                            KeyNavigation.backtab: powerButton
                            KeyNavigation.tab: hibernateButton
                        }

                        Button {
                            id: hibernateButton
                            text: "Hibernate"
                            width: compactLayout ? actionsFlow.width : 118
                            height: buttonHeight
                            visible: sddm.canHibernate
                            onClicked: sddm.hibernate()
                            KeyNavigation.backtab: suspendButton
                            KeyNavigation.tab: sessionBox
                        }
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        if (userEntry.text === "") {
            userEntry.focus = true
        } else {
            passwordEntry.focus = true
        }

        topDate.text = Qt.formatDateTime(new Date(), "dddd, dd MMM yyyy  HH:mm")
        heroDate.text = Qt.formatDateTime(new Date(), "dddd, dd MMMM")

        topBar.opacity = 1.0
        topBar.scale = 1.0
        contentDock.opacity = 1.0
        contentDock.scale = 1.0
        screenReady = true
    }
}
