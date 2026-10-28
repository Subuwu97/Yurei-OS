// Yūrei login screen for SDDM (Qt 6).
//
// Recreates the approved design (branding/source/Yurei-Login-Reference.png,
// 1672x941) with real controls: the wordmark, avatar, name, password field
// and "Switch user" sit at the design's own coordinates over the artwork, so
// they cover the spots where the mock-up was painted; the session menu and
// power controls sit in the screen corners, as in the design.
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

    // LOGIN_LAYOUT: positions below are pixels of the 1672x941 design
    readonly property real designWidth: 1672
    readonly property real designHeight: 941
    readonly property real columnX: 555  // centre of the avatar and password field

    readonly property real s: Math.max(width / designWidth, height / designHeight)
    // control size: follows the artwork, capped on narrow (portrait) screens
    readonly property real k: Math.min(s, width * 0.82 / 368)
    // corner controls: follow the artwork too, but stay small enough to fit
    readonly property real c: Math.min(k, width / 900)
    readonly property real artWidth: designWidth * s
    readonly property real artHeight: designHeight * s
    // anchor the art to the right so the mascot stays in frame, but never
    // push the login column off the left edge on narrow screens
    readonly property real artX: Math.min(0, Math.max(width - artWidth, 184 * k + 24 - columnX * s))
    readonly property real artY: (height - artHeight) / 2
    function designX(x) { return artX + x * s }
    function designY(y) { return artY + y * s }

    // --- state ---------------------------------------------------------------

    property bool manualLogin: userModel.count === 0 || config.forceUserField === "true"
    property int userIndex: userModel.lastIndex >= 0 ? userModel.lastIndex : 0
    readonly property var user: users.count > 0 ? users.itemAt(Math.min(userIndex, users.count - 1)) : null
    readonly property string userName: manualLogin ? usernameField.text : (user ? user.userName : "")
    readonly property string displayName: user ? (user.userRealName || user.userName) : ""
    property bool busy: false
    property string error: ""

    function login() {
        if (busy || userName.length === 0)
            return
        busy = true
        error = ""
        sddm.login(userName, password.text, session.currentIndex)
    }

    function chooseUser(index) {
        manualLogin = false
        userIndex = index
        password.text = ""
        error = ""
        password.forceActiveFocus()
    }

    function typeUsername() {
        manualLogin = true
        error = ""
        usernameField.text = ""  // switching means another account
        usernameField.forceActiveFocus()
    }

    function switchUser(step) {
        if (userModel.count > 1)
            chooseUser((userIndex + step + userModel.count) % userModel.count)
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
        x: root.artX
        y: root.artY
        width: root.artWidth
        height: root.artHeight
        source: config.background || "assets/background.jpg"
        fillMode: Image.Stretch
        smooth: true
    }

    // --- login column ----------------------------------------------------------

    Image {
        id: logo
        source: "assets/logo.png"
        // the wordmark's box in the design: x 349.6, y 170.6, 464.7 wide
        width: 464.7 * root.k
        height: width * 0.4
        x: root.designX(349.6 + 464.7 / 2) - width / 2
        y: root.designY(170.6)
        sourceSize.width: width
        smooth: true
        mipmap: true
        Accessible.name: "Yūrei"
    }

    Avatar {
        id: avatar
        objectName: "avatar"
        width: 128 * root.k
        height: width
        x: root.designX(root.columnX) - width / 2
        y: root.designY(457) - height / 2
        source: !root.manualLogin && root.user && root.user.userIcon ? root.user.userIcon : ""
        fallback: Qt.resolvedUrl("assets/avatar.png")
        name: root.manualLogin ? usernameField.text : root.displayName
    }

    Text {
        id: userLabel
        objectName: "userLabel"
        visible: !root.manualLogin
        anchors.horizontalCenter: avatar.horizontalCenter
        y: root.designY(553) - height / 2
        text: root.displayName
        color: "#ffffff"
        font.pixelSize: 25 * root.k
        style: Text.Raised
        styleColor: "#80060c1f"
    }

    Column {
        id: form
        width: 368 * root.k
        x: root.designX(root.columnX + 1) - width / 2
        y: root.designY(root.manualLogin ? 528 : 582)
        spacing: 8 * root.k

        TextField {
            id: usernameField
            objectName: "usernameField"
            visible: root.manualLogin
            width: parent.width
            height: 46 * root.k
            placeholderText: "Username"
            placeholderTextColor: "#9d97c9"
            color: "#ffffff"
            font.pixelSize: 16 * root.k
            leftPadding: 24 * root.k
            text: userModel.lastUser || ""
            Accessible.name: "Username"
            KeyNavigation.tab: password
            Keys.onReturnPressed: password.forceActiveFocus()
            Keys.onEnterPressed: password.forceActiveFocus()
            background: Rectangle {
                radius: height / 2
                color: "#cc0b0f2b"
                border.width: usernameField.activeFocus ? 2 : 1.5
                border.color: usernameField.activeFocus ? "#e2dcff" : "#b9b0f0"
            }
        }

        Item {
            id: passwordBox
            width: parent.width
            height: 60 * root.k

            TextField {
                id: password
                objectName: "password"
                anchors.fill: parent
                echoMode: TextInput.Password
                passwordCharacter: "●"
                placeholderText: "Password"
                placeholderTextColor: "#9d97c9"
                color: "#ffffff"
                font.pixelSize: 16 * root.k
                leftPadding: 62 * root.k
                rightPadding: 62 * root.k
                enabled: !root.busy
                focus: !root.manualLogin
                Accessible.name: "Password for " + root.userName
                Keys.onReturnPressed: root.login()
                Keys.onEnterPressed: root.login()
                Keys.onEscapePressed: { text = ""; root.error = "" }
                Keys.onUpPressed: event => { if (text.length === 0) root.switchUser(-1); else event.accepted = false }
                Keys.onDownPressed: event => { if (text.length === 0) root.switchUser(1); else event.accepted = false }
                onTextChanged: if (text.length) root.error = ""
                KeyNavigation.tab: submit
                background: Rectangle {
                    radius: height / 2
                    color: "#d90b0f2b"
                    border.width: password.activeFocus ? 2 : 1.5
                    border.color: root.error ? "#ff9ab8" : password.activeFocus ? "#e2dcff" : "#b9b0f0"
                    Behavior on border.color { ColorAnimation { duration: 150 } }
                }
            }

            Image {
                anchors.left: parent.left
                anchors.leftMargin: 22 * root.k
                anchors.verticalCenter: parent.verticalCenter
                width: 20 * root.k
                height: width
                sourceSize: Qt.size(width * 2, height * 2)
                source: "assets/icons/lock.svg"
            }

            AbstractButton {
                id: submit
                objectName: "submit"
                anchors.right: parent.right
                anchors.rightMargin: 8 * root.k
                anchors.verticalCenter: parent.verticalCenter
                width: 46 * root.k
                height: width
                enabled: !root.busy
                focusPolicy: Qt.StrongFocus
                Accessible.name: "Log in"
                onClicked: root.login()
                Keys.onReturnPressed: root.login()
                Keys.onEnterPressed: root.login()
                KeyNavigation.tab: switchUser
                background: Rectangle {
                    radius: width / 2
                    border.width: submit.activeFocus ? 2 : 0
                    border.color: "#ffffff"
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: submit.down ? "#7d6be6" : submit.hovered ? "#b3a4ff" : "#a594ff" }
                        GradientStop { position: 1.0; color: submit.down ? "#5f4fc4" : "#7b6af0" }
                    }
                }
                contentItem: Item {
                    Image {
                        anchors.centerIn: parent
                        visible: !root.busy
                        width: parent.width * 0.48
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
    }

    AbstractButton {  // "Switch user": a list of accounts, or type a username
        id: switchUser
        objectName: "switchUser"
        anchors.horizontalCenter: form.horizontalCenter
        y: root.designY(672) - height / 2
        visible: userModel.count > 0
        focusPolicy: Qt.StrongFocus
        Accessible.name: text
        text: root.manualLogin ? "Back" : "Switch user"
        KeyNavigation.tab: session
        onClicked: {
            if (root.manualLogin)
                root.chooseUser(root.userIndex)
            else if (userModel.count > 1)
                userMenu.open()
            else
                root.typeUsername()
        }
        Keys.onReturnPressed: clicked()
        Keys.onEnterPressed: clicked()
        contentItem: Text {
            text: switchUser.text
            color: switchUser.hovered || switchUser.activeFocus ? "#ffffff" : "#cdc6ff"
            font.pixelSize: 17 * root.k
            font.underline: switchUser.activeFocus
            style: Text.Raised
            styleColor: "#c0060c1f"
        }
        background: null
    }

    Text {  // errors and warnings, announced to screen readers
        objectName: "message"
        anchors.horizontalCenter: form.horizontalCenter
        y: root.designY(700)
        width: form.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: root.error ? root.error : keyboard.capsLock ? "Caps Lock is on" : ""
        color: root.error ? "#ffb4c9" : "#ffe3a3"
        font.pixelSize: 15 * root.k
        style: Text.Raised
        styleColor: "#c0060c1f"
        Accessible.role: Accessible.AlertMessage
        Accessible.name: text
    }

    Popup {  // the account list behind "Switch user"
        id: userMenu
        objectName: "userMenu"
        x: form.x
        y: switchUser.y + switchUser.height + 8 * root.k
        width: form.width
        padding: 6 * root.k
        modal: true
        focus: true
        onOpened: userList.forceActiveFocus()
        background: Rectangle {
            radius: 16 * root.k
            color: "#f00b0f2b"
            border.color: "#b9b0f0"
        }
        contentItem: ListView {
            id: userList
            implicitHeight: contentHeight
            interactive: false
            currentIndex: root.userIndex
            keyNavigationEnabled: true
            model: userModel.count + 1  // every account, then "Other user"
            Keys.onReturnPressed: activate(currentIndex)
            Keys.onEnterPressed: activate(currentIndex)
            function activate(index) {
                userMenu.close()
                if (index < userModel.count)
                    root.chooseUser(index)
                else
                    root.typeUsername()
            }
            delegate: ItemDelegate {
                required property int index
                readonly property var account: index < users.count ? users.itemAt(index) : null
                width: userList.width
                height: 44 * root.k
                highlighted: ListView.isCurrentItem
                onClicked: userList.activate(index)
                contentItem: Text {
                    text: account ? (account.userRealName || account.userName) : "Other user…"
                    color: "#ffffff"
                    font.pixelSize: 16 * root.k
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: 10 * root.k
                }
                background: Rectangle {
                    radius: 10 * root.k
                    color: highlighted || hovered ? "#4d3f8f" : "transparent"
                }
            }
        }
    }

    // --- bottom left: session ----------------------------------------------------

    IconButton {  // the gear opens the session menu, as in the design
        id: gear
        x: 67 * root.c - width / 2
        y: root.height - 69 * root.c - height / 2
        size: 50 * root.c
        glyph: 0.56
        iconSource: Qt.resolvedUrl("assets/icons/gear.svg")
        tip: "Session"
        focusPolicy: Qt.NoFocus
        onClicked: session.popup.open()
    }

    ComboBox {
        id: session
        objectName: "session"
        model: sessionModel
        textRole: "name"
        currentIndex: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0
        x: 99 * root.c
        y: root.height - 69 * root.c - height / 2
        // the design's pill is 166 wide; grow to fit names like "Plasma (Wayland)"
        width: Math.min(Math.max(166 * root.c, sessionName.width + 64 * root.c), 320 * root.c)
        height: 43 * root.c
        leftPadding: 0  // the text's own padding below leaves room for the arrow
        rightPadding: 0
        font.pixelSize: 17 * root.c
        Accessible.name: "Session"
        TextMetrics {
            id: sessionName
            font: session.font
            text: session.displayText
        }
        KeyNavigation.tab: layoutButton.switchable ? layoutButton : suspendButton

        background: Rectangle {
            radius: height / 2
            color: session.pressed ? "#cc2a2458" : "#b30b0f2b"
            border.width: session.activeFocus ? 2 : 1.5
            border.color: session.activeFocus ? "#e2dcff" : "#b9b0f0"
        }
        contentItem: Text {
            leftPadding: 20 * root.c
            rightPadding: 40 * root.c
            verticalAlignment: Text.AlignVCenter
            text: session.displayText
            color: "#ffffff"
            font: session.font
            elide: Text.ElideRight
        }
        indicator: Image {
            x: session.width - width - 16 * root.c
            anchors.verticalCenter: parent.verticalCenter
            source: "assets/icons/chevron.svg"
            width: 16 * root.c
            height: width
            sourceSize: Qt.size(width * 2, height * 2)
            rotation: session.popup.visible ? 180 : 0
        }
        delegate: ItemDelegate {
            required property var model
            required property int index
            width: Math.max(session.width, 260 * root.c)
            highlighted: session.highlightedIndex === index
            contentItem: Text {
                text: model.name
                color: "#ffffff"
                font: session.font
                elide: Text.ElideRight
            }
            background: Rectangle {
                color: highlighted ? "#4d3f8f" : "transparent"
                radius: 8
            }
        }
        popup: Popup {
            y: -implicitHeight - 8
            width: Math.max(session.width, 260 * root.c)
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
                color: "#f00b0f2b"
                border.color: "#b9b0f0"
            }
        }
    }

    // --- bottom right: keyboard layout and power ------------------------------------

    AbstractButton {
        id: layoutButton
        objectName: "layoutButton"
        readonly property bool switchable: keyboard.layouts.length > 1
        visible: keyboard.layouts.length > 0
        x: root.width - 268 * root.c - width / 2
        y: root.height - 69 * root.c - height / 2
        width: 50 * root.c
        height: width
        enabled: switchable
        focusPolicy: switchable ? Qt.StrongFocus : Qt.NoFocus
        Accessible.name: visible ? "Keyboard layout: " + keyboard.layouts[keyboard.currentLayout].longName : ""
        onClicked: keyboard.currentLayout = (keyboard.currentLayout + 1) % keyboard.layouts.length
        Keys.onReturnPressed: clicked()
        Keys.onSpacePressed: clicked()
        KeyNavigation.tab: suspendButton
        contentItem: Text {
            text: layoutButton.visible ? keyboard.layouts[keyboard.currentLayout].shortName.toUpperCase() : ""
            color: "#ffffff"
            font.pixelSize: 17 * root.c
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: width / 2
            color: layoutButton.hovered && layoutButton.switchable ? "#80241f55" : "transparent"
            border.width: layoutButton.activeFocus ? 2 : 0
            border.color: "#d6ccff"
        }
        ToolTip.visible: hovered && switchable
        ToolTip.text: "Switch keyboard layout"
    }

    IconButton {
        id: suspendButton
        objectName: "suspendButton"
        visible: sddm.canSuspend
        x: root.width - 201 * root.c - width / 2
        y: root.height - 69 * root.c - height / 2
        size: 60 * root.c
        iconSource: Qt.resolvedUrl("assets/icons/moon.svg")
        tip: "Sleep"
        onClicked: sddm.suspend()
        KeyNavigation.tab: rebootButton
    }
    IconButton {
        id: rebootButton
        objectName: "rebootButton"
        visible: sddm.canReboot
        x: root.width - 134 * root.c - width / 2
        y: root.height - 69 * root.c - height / 2
        size: 60 * root.c
        iconSource: Qt.resolvedUrl("assets/icons/restart.svg")
        tip: "Restart"
        onClicked: sddm.reboot()
        KeyNavigation.tab: powerButton
    }
    IconButton {
        id: powerButton
        objectName: "powerButton"
        visible: sddm.canPowerOff
        x: root.width - 67 * root.c - width / 2
        y: root.height - 69 * root.c - height / 2
        size: 60 * root.c
        iconSource: Qt.resolvedUrl("assets/icons/power.svg")
        tip: "Shut down"
        onClicked: sddm.powerOff()
        KeyNavigation.tab: root.manualLogin ? usernameField : password
    }

    Rectangle {  // fade out after a successful login
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
