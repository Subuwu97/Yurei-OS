// Yūrei login screen for SDDM (Qt 6).
//
// Layout follows the approved design: shrine and sakura on the left, the
// mascot on the right, and the wordmark, avatar and password field in the
// gap between them. Those controls are positioned in the artwork's own
// coordinates, so they stay in that gap on every screen shape; the session
// menu and power buttons sit in the screen corners.
//
// Context objects provided by SDDM: sddm, userModel, sessionModel, keyboard,
// config (theme.conf).

import QtQuick
import QtQuick.Controls
import "components"

Rectangle {
    id: root

    width: 1920
    height: 1080
    color: "#060c1f"

    // --- where the artwork lands on this screen -----------------------------

    // pixel size of the design the coordinates below refer to
    readonly property real designWidth: 1505
    readonly property real designHeight: 631
    // centre of the gap between shrine and mascot, in design pixels
    readonly property real columnX: 713

    readonly property real s: Math.max(width / designWidth, height / designHeight)
    // size of the login controls: follows the artwork, but on portrait
    // screens (where the art is cropped hard) it's capped by the width
    readonly property real k: Math.min(s, width * 0.82 / 360)
    readonly property real artWidth: designWidth * s
    readonly property real artHeight: designHeight * s
    // anchor the art to the right so the mascot stays in frame, but never
    // push the login column off the left edge on narrow screens
    readonly property real columnHalf: 190 * k
    readonly property real artX: Math.min(0, Math.max(width - artWidth,
                                                      columnHalf + 24 - columnX * s))
    readonly property real artY: (height - artHeight) / 2
    readonly property real centerX: artX + columnX * s
    function designY(y) { return artY + y * s }

    // text and corner controls scale with the screen, within limits
    readonly property real ui: Math.max(0.75, Math.min(2.2, height / 1080))

    // --- state ---------------------------------------------------------------

    property bool manualLogin: userModel.count === 0 || config.forceUserField === "true"
    property int userIndex: userModel.lastIndex >= 0 ? userModel.lastIndex : 0
    readonly property var user: users.count > 0 ? users.itemAt(Math.min(userIndex, users.count - 1)) : null
    readonly property string userName: manualLogin ? usernameField.text : (user ? user.userName : "")
    property bool busy: false
    property string error: ""

    function login() {
        if (busy || userName.length === 0)
            return
        busy = true
        error = ""
        sddm.login(userName, password.text, session.currentIndex)
    }

    function switchUser(step) {
        if (userModel.count < 2)
            return
        userIndex = (userIndex + step + userModel.count) % userModel.count
        password.text = ""
        error = ""
        password.forceActiveFocus()
    }

    Repeater {  // exposes each user's name, real name and picture
        id: users
        model: userModel
        delegate: Item {
            property string userName: model.name
            property string userRealName: model.realName || ""
            property string userIcon: model.icon || ""
        }
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            root.busy = false
            root.error = keyboard.capsLock ? "Wrong password - Caps Lock is on"
                                           : "Wrong password - please try again"
            password.text = ""
            shake.restart()
            password.forceActiveFocus()
        }
        function onLoginSucceeded() {
            fadeOut.start()
        }
    }

    // --- artwork ---------------------------------------------------------------

    Image {
        id: art
        x: root.artX
        y: root.artY
        width: root.artWidth
        height: root.artHeight
        source: config.background || "assets/background.jpg"
        fillMode: Image.Stretch
        smooth: true
        asynchronous: false
    }

    // --- login column ----------------------------------------------------------

    Image {
        id: logo
        source: "assets/logo.png"
        width: 290 * root.k
        height: width / 2
        x: root.centerX - width / 2
        y: root.designY(152)
        sourceSize.width: width
        smooth: true
        mipmap: true
        Accessible.name: "Yūrei"
    }

    Avatar {
        id: avatar
        objectName: "avatar"
        width: 92 * root.k
        height: width
        x: root.centerX - width / 2
        y: root.designY(287)
        visible: !root.manualLogin
        source: root.user && root.user.userIcon ? root.user.userIcon : ""
        name: root.user ? (root.user.userRealName || root.user.userName) : ""
    }

    Row {  // user name, with arrows when there are several users
        id: nameRow
        objectName: "nameRow"
        anchors.horizontalCenter: avatar.horizontalCenter
        y: root.designY(388)
        spacing: 10 * root.k
        visible: !root.manualLogin

        Image {
            anchors.verticalCenter: parent.verticalCenter
            visible: userModel.count > 1
            source: "assets/icons/left.svg"
            width: 14 * root.k
            height: width
            sourceSize: Qt.size(width * 2, height * 2)
            opacity: prevArea.containsMouse ? 1 : 0.65
            MouseArea { id: prevArea; anchors.fill: parent; anchors.margins: -8; hoverEnabled: true; onClicked: root.switchUser(-1) }
        }
        Text {
            objectName: "userLabel"
            text: root.user ? (root.user.userRealName || root.user.userName) : ""
            color: "#f6f2ff"
            font.pixelSize: 17 * root.k
            font.weight: Font.DemiBold
            style: Text.Raised
            styleColor: "#80060c1f"
        }
        Image {
            anchors.verticalCenter: parent.verticalCenter
            visible: userModel.count > 1
            source: "assets/icons/right.svg"
            width: 14 * root.k
            height: width
            sourceSize: Qt.size(width * 2, height * 2)
            opacity: nextArea.containsMouse ? 1 : 0.65
            MouseArea { id: nextArea; anchors.fill: parent; anchors.margins: -8; hoverEnabled: true; onClicked: root.switchUser(1) }
        }
    }

    Column {
        id: form
        width: 330 * root.k
        x: root.centerX - width / 2
        y: root.manualLogin ? root.designY(330) : root.designY(424)
        spacing: 10 * root.k

        TextField {
            id: usernameField
            objectName: "usernameField"
            visible: root.manualLogin
            width: parent.width
            height: 46 * root.k
            placeholderText: "Username"
            placeholderTextColor: "#a99fd6"
            color: "#f6f2ff"
            font.pixelSize: 14 * root.k
            leftPadding: 22 * root.k
            text: userModel.lastUser || ""
            KeyNavigation.tab: password
            Keys.onReturnPressed: password.forceActiveFocus()
            Keys.onEnterPressed: password.forceActiveFocus()
            background: Rectangle {
                radius: height / 2
                color: "#cc0e1430"
                border.width: usernameField.activeFocus ? 2 : 1
                border.color: usernameField.activeFocus ? "#cbbcff" : "#80b9aaff"
            }
        }

        Item {
            id: passwordBox
            width: parent.width
            height: 50 * root.k

            TextField {
                id: password
            objectName: "password"
                anchors.fill: parent
                echoMode: TextInput.Password
                passwordCharacter: "●"
                placeholderText: "Password"
                placeholderTextColor: "#c9c0f0"
                color: "#f6f2ff"
                font.pixelSize: 14 * root.k
                leftPadding: 52 * root.k
                rightPadding: 56 * root.k
                enabled: !root.busy
                focus: !root.manualLogin
                Accessible.name: "Password for " + root.userName
                Keys.onReturnPressed: root.login()
                Keys.onEnterPressed: root.login()
                Keys.onEscapePressed: { text = ""; root.error = "" }
                Keys.onLeftPressed: event => { if (text.length === 0) root.switchUser(-1); else event.accepted = false }
                Keys.onRightPressed: event => { if (text.length === 0) root.switchUser(1); else event.accepted = false }
                onTextChanged: if (text.length) root.error = ""
                KeyNavigation.tab: submit
                background: Rectangle {
                    radius: height / 2
                    color: "#d00e1430"
                    border.width: password.activeFocus ? 2 : 1
                    border.color: root.error ? "#ff9ab8" : password.activeFocus ? "#cbbcff" : "#99b9aaff"
                    Behavior on border.color { ColorAnimation { duration: 150 } }
                }
            }

            Image {
                anchors.left: parent.left
                anchors.leftMargin: 20 * root.k
                anchors.verticalCenter: parent.verticalCenter
                width: 18 * root.k
                height: width
                sourceSize: Qt.size(width * 2, height * 2)
                source: "assets/icons/lock.svg"
                opacity: 0.85
            }

            AbstractButton {
                id: submit
            objectName: "submit"
                anchors.right: parent.right
                anchors.rightMargin: 6 * root.k
                anchors.verticalCenter: parent.verticalCenter
                width: 40 * root.k
                height: width
                enabled: !root.busy
                focusPolicy: Qt.StrongFocus
                Accessible.name: "Log in"
                onClicked: root.login()
                Keys.onReturnPressed: root.login()
                Keys.onEnterPressed: root.login()
                KeyNavigation.tab: session
                background: Rectangle {
                    radius: width / 2
                    color: submit.down ? "#b9aaff" : submit.hovered || submit.activeFocus ? "#ece6ff" : "#d9d0ff"
                    border.width: submit.activeFocus ? 2 : 0
                    border.color: "#ffffff"
                }
                contentItem: Item {
                    Image {
                        anchors.centerIn: parent
                        visible: !root.busy
                        width: parent.width * 0.5
                        height: width
                        sourceSize: Qt.size(width * 2, height * 2)
                        source: "assets/icons/arrow.svg"
                    }
                    BusyIndicator {
                        anchors.centerIn: parent
                        running: root.busy
                        visible: root.busy
                        width: parent.width * 0.8
                        height: width
                    }
                }
            }

            SequentialAnimation {  // a little "no" shake on a wrong password
                id: shake
                NumberAnimation { target: passwordBox; property: "x"; to: -12; duration: 50 }
                NumberAnimation { target: passwordBox; property: "x"; to: 10; duration: 70 }
                NumberAnimation { target: passwordBox; property: "x"; to: -6; duration: 70 }
                NumberAnimation { target: passwordBox; property: "x"; to: 0; duration: 60 }
            }
        }

        Text {  // errors and warnings, announced to screen readers
            objectName: "message"
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root.error ? root.error
                  : keyboard.capsLock ? "Caps Lock is on" : ""
            color: root.error ? "#ffb4c9" : "#ffe3a3"
            font.pixelSize: 13 * root.k
            style: Text.Raised
            styleColor: "#c0060c1f"
            Accessible.role: Accessible.AlertMessage
            Accessible.name: text
        }
    }

    Text {  // switch between picking a user and typing a username
        anchors.horizontalCenter: form.horizontalCenter
        y: root.designY(512)
        visible: userModel.count > 0
        text: root.manualLogin ? "Choose a user" : "Other user"
        color: otherArea.containsMouse ? "#ffffff" : "#ddd6ff"
        font.pixelSize: 12 * root.k
        font.underline: otherArea.containsMouse
        style: Text.Raised
        styleColor: "#c0060c1f"
        MouseArea {
            id: otherArea
            anchors.fill: parent
            anchors.margins: -6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                root.manualLogin = !root.manualLogin
                root.error = ""
                if (root.manualLogin) usernameField.forceActiveFocus()
                else password.forceActiveFocus()
            }
        }
    }

    // --- bottom left: session and keyboard layout --------------------------------

    Row {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 28 * root.ui
        spacing: 12 * root.ui

        ComboBox {
            id: session
            objectName: "session"
            model: sessionModel
            textRole: "name"
            currentIndex: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0
            width: 210 * root.ui
            height: 46 * root.ui
            font.pixelSize: 14 * root.ui
            Accessible.name: "Session"
            KeyNavigation.tab: layoutButton.visible ? layoutButton : suspendButton

            background: Rectangle {
                radius: height / 2
                color: session.pressed ? "#2a2658" : "#c0101530"
                border.width: session.activeFocus ? 2 : 1
                border.color: session.activeFocus ? "#cbbcff" : "#66b9aaff"
            }
            contentItem: Row {
                leftPadding: 16 * root.ui
                spacing: 10 * root.ui
                Image {
                    anchors.verticalCenter: parent.verticalCenter
                    source: "assets/icons/gear.svg"
                    width: 18 * root.ui
                    height: width
                    sourceSize: Qt.size(width * 2, height * 2)
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: session.width - 90 * root.ui
                    text: session.displayText
                    color: "#f6f2ff"
                    font: session.font
                    elide: Text.ElideRight
                }
            }
            indicator: Image {
                x: session.width - width - 16 * root.ui
                anchors.verticalCenter: parent.verticalCenter
                source: "assets/icons/chevron.svg"
                width: 16 * root.ui
                height: width
                sourceSize: Qt.size(width * 2, height * 2)
                rotation: session.popup.visible ? 180 : 0
            }
            delegate: ItemDelegate {
                required property var model
                required property int index
                width: session.width
                highlighted: session.highlightedIndex === index
                contentItem: Text {
                    text: model.name
                    color: "#f6f2ff"
                    font: session.font
                    elide: Text.ElideRight
                }
                background: Rectangle {
                    color: highlighted ? "#3a3470" : "transparent"
                    radius: 8
                }
            }
            popup: Popup {
                y: -implicitHeight - 8
                width: session.width
                implicitHeight: contentItem.implicitHeight + 12
                padding: 6
                contentItem: ListView {
                    clip: true
                    implicitHeight: contentHeight
                    model: session.popup.visible ? session.delegateModel : null
                    currentIndex: session.highlightedIndex
                }
                background: Rectangle {
                    radius: 14
                    color: "#f0101530"
                    border.color: "#66b9aaff"
                }
            }
        }

        IconButton {
            id: layoutButton
            objectName: "layoutButton"
            visible: keyboard.layouts.length > 1
            size: 46 * root.ui
            iconSource: Qt.resolvedUrl("assets/icons/keyboard.svg")
            tip: visible ? "Keyboard layout: " + keyboard.layouts[keyboard.currentLayout].longName : ""
            onClicked: keyboard.currentLayout = (keyboard.currentLayout + 1) % keyboard.layouts.length
            KeyNavigation.tab: suspendButton
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.bottom
                anchors.topMargin: 2
                text: parent.visible ? keyboard.layouts[keyboard.currentLayout].shortName.toUpperCase() : ""
                color: "#c9c0f0"
                font.pixelSize: 10 * root.ui
            }
        }
    }

    // --- bottom right: power ---------------------------------------------------

    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 28 * root.ui
        spacing: 14 * root.ui

        IconButton {
            id: suspendButton
            objectName: "suspendButton"
            visible: sddm.canSuspend
            size: 52 * root.ui
            iconSource: Qt.resolvedUrl("assets/icons/moon.svg")
            tip: "Sleep"
            onClicked: sddm.suspend()
            KeyNavigation.tab: rebootButton
        }
        IconButton {
            id: rebootButton
            objectName: "rebootButton"
            visible: sddm.canReboot
            size: 52 * root.ui
            iconSource: Qt.resolvedUrl("assets/icons/restart.svg")
            tip: "Restart"
            onClicked: sddm.reboot()
            KeyNavigation.tab: powerButton
        }
        IconButton {
            id: powerButton
            objectName: "powerButton"
            visible: sddm.canPowerOff
            size: 52 * root.ui
            iconSource: Qt.resolvedUrl("assets/icons/power.svg")
            tip: "Shut down"
            onClicked: sddm.powerOff()
            KeyNavigation.tab: root.manualLogin ? usernameField : password
        }
    }

    Rectangle {  // fade to the session's colour after a successful login
        id: curtain
        anchors.fill: parent
        color: "#060c1f"
        opacity: 0
        NumberAnimation on opacity { id: fadeOut; running: false; to: 1; duration: 400 }
    }

    Component.onCompleted: {
        if (manualLogin)
            usernameField.forceActiveFocus()
        else
            password.forceActiveFocus()
    }
}
