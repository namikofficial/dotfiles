import QtQuick 2.0
import SddmComponents 2.0

Rectangle {
    id: root
    width: 1920
    height: 1080
    color: "#0f111a"

    LayoutMirroring.enabled: Qt.locale().textDirection == Qt.RightToLeft
    LayoutMirroring.childrenInherit: true

    property color accent: "#7aa2f7"
    property color panelBg: "#dd121725"
    property color panelBorder: "#447aa2f7"
    property color textPrimary: "#c0caf5"
    property color textMuted: "#9aa5ce"
    property color okColor: "#4fd6be"
    property color badColor: "#ff757f"
    property string statusMessage: textConstants.prompt
    property color statusColor: textMuted

    TextConstants { id: textConstants }

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
        color: "#780d111b"
    }

    Rectangle {
        id: topBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 56
        color: "#b5121724"
        border.color: "#2b7aa2f7"
        border.width: 1

        Text {
            id: topDate
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 16
            color: textPrimary
            font.pixelSize: 14
            font.bold: true
        }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: 16
            spacing: 8

            Text {
                text: textConstants.session
                color: textMuted
                font.pixelSize: 13
            }

            ComboBox {
                id: sessionBox
                width: 250
                height: 34
                arrowIcon: "angle-down.png"
                model: sessionModel
                index: sessionModel.lastIndex
                font.pixelSize: 13
                KeyNavigation.backtab: powerButton
                KeyNavigation.tab: layoutBox
            }

            Text {
                text: textConstants.layout
                color: textMuted
                font.pixelSize: 13
            }

            LayoutBox {
                id: layoutBox
                width: 100
                height: 34
                arrowIcon: "angle-down.png"
                font.pixelSize: 13
                KeyNavigation.backtab: sessionBox
                KeyNavigation.tab: userEntry
            }
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            topDate.text = Qt.formatDateTime(new Date(), "dddd, dd MMM yyyy  HH:mm")
            panelDate.text = Qt.formatDateTime(new Date(), "dddd, dd MMMM")
        }
    }

    Rectangle {
        id: panel
        width: 620
        height: 420
        anchors.centerIn: parent
        radius: 18
        color: panelBg
        border.width: 1
        border.color: panelBorder

        Column {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 12

            Text {
                text: sddm.hostName
                color: accent
                font.pixelSize: 28
                font.bold: true
            }

            Text {
                id: panelDate
                color: textMuted
                font.pixelSize: 14
            }

            Text {
                text: textConstants.userName
                color: textMuted
                font.pixelSize: 13
                font.bold: true
            }

            Row {
                spacing: 10

                Image {
                    source: "images/user_icon.png"
                    width: 32
                    height: 32
                    anchors.verticalCenter: parent.verticalCenter
                }

                TextBox {
                    id: userEntry
                    width: 520
                    height: 42
                    text: userModel.lastUser
                    font.pixelSize: 16
                    KeyNavigation.backtab: layoutBox
                    KeyNavigation.tab: passwordEntry
                    Keys.onPressed: {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            sddm.login(userEntry.text, passwordEntry.text, sessionBox.index)
                            event.accepted = true
                        }
                    }
                }
            }

            Text {
                text: textConstants.password
                color: textMuted
                font.pixelSize: 13
                font.bold: true
            }

            Row {
                spacing: 10

                Image {
                    source: "images/lock.png"
                    width: 32
                    height: 32
                    anchors.verticalCenter: parent.verticalCenter
                }

                PasswordBox {
                    id: passwordEntry
                    width: 520
                    height: 42
                    font.pixelSize: 16
                    tooltipBG: accent
                    KeyNavigation.backtab: userEntry
                    KeyNavigation.tab: loginButton
                    Keys.onPressed: {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            sddm.login(userEntry.text, passwordEntry.text, sessionBox.index)
                            event.accepted = true
                        }
                    }
                }
            }

            Text {
                text: statusMessage
                color: statusColor
                font.pixelSize: 13
                wrapMode: Text.WordWrap
                width: parent.width
                elide: Text.ElideRight
            }

            Row {
                spacing: 8

                Button {
                    id: loginButton
                    text: textConstants.login
                    width: 145
                    onClicked: sddm.login(userEntry.text, passwordEntry.text, sessionBox.index)
                    KeyNavigation.backtab: passwordEntry
                    KeyNavigation.tab: rebootButton
                }

                Button {
                    id: rebootButton
                    text: textConstants.reboot
                    width: 120
                    onClicked: sddm.reboot()
                    KeyNavigation.backtab: loginButton
                    KeyNavigation.tab: powerButton
                }

                Button {
                    id: powerButton
                    text: textConstants.shutdown
                    width: 120
                    onClicked: sddm.powerOff()
                    KeyNavigation.backtab: rebootButton
                    KeyNavigation.tab: suspendButton
                }

                Button {
                    id: suspendButton
                    text: "Suspend"
                    width: 110
                    visible: sddm.canSuspend
                    onClicked: sddm.suspend()
                    KeyNavigation.backtab: powerButton
                    KeyNavigation.tab: hibernateButton
                }

                Button {
                    id: hibernateButton
                    text: "Hibernate"
                    width: 110
                    visible: sddm.canHibernate
                    onClicked: sddm.hibernate()
                    KeyNavigation.backtab: suspendButton
                    KeyNavigation.tab: sessionBox
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
        panelDate.text = Qt.formatDateTime(new Date(), "dddd, dd MMMM")
    }
}
