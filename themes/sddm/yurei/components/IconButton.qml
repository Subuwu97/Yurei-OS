import QtQuick
import QtQuick.Controls

// A white glyph on a soft dark disc, as in the design's power controls.
AbstractButton {
    id: control

    property url iconSource
    property real size: 58
    property real glyph: 0.5  // glyph size as a fraction of the disc
    property string tip

    implicitWidth: size
    implicitHeight: size
    focusPolicy: Qt.StrongFocus
    Accessible.name: tip
    Keys.onReturnPressed: clicked()
    Keys.onEnterPressed: clicked()

    background: Rectangle {
        radius: width / 2
        color: control.down ? "#99302a66" : control.hovered ? "#80241f55" : "#400b0e2a"
        border.width: control.activeFocus ? 2 : 0
        border.color: "#d6ccff"
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    contentItem: Item {
        Image {
            anchors.centerIn: parent
            width: control.size * control.glyph
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
