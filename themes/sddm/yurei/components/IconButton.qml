import QtQuick
import QtQuick.Controls

// Round glass button with an SVG icon, used for the power controls.
AbstractButton {
    id: control

    property url iconSource
    property real size: 52
    property string tip

    implicitWidth: size
    implicitHeight: size
    focusPolicy: Qt.StrongFocus
    Accessible.name: tip
    Keys.onReturnPressed: clicked()
    Keys.onEnterPressed: clicked()

    background: Rectangle {
        radius: width / 2
        color: control.down ? "#3a3470" : control.hovered ? "#2a2658" : "#c0101530"
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? "#cbbcff" : "#66b9aaff"
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    contentItem: Item {
        Image {
            anchors.centerIn: parent
            width: control.size * 0.46
            height: width
            sourceSize: Qt.size(width * 2, height * 2)
            source: control.iconSource
            opacity: control.enabled ? 1 : 0.4
        }
    }

    ToolTip.visible: hovered && tip.length > 0
    ToolTip.text: tip
    ToolTip.delay: 400
}
