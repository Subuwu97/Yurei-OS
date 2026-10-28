import QtQuick

// Circular user picture with a glowing ring. Falls back to the first letter
// of the name on a moonlit gradient when the user has no picture.
// Drawn with Canvas rather than a shader effect so it also works with
// software rendering (VMs, machines before GPU drivers are installed).
Item {
    id: avatar

    property url source
    property string name

    readonly property bool hasPicture: picture.status === Image.Ready

    Rectangle {  // soft outer glow
        anchors.centerIn: parent
        width: parent.width + 14
        height: width
        radius: width / 2
        color: "transparent"
        border.width: 6
        border.color: "#33a99bff"
    }

    Image {  // loaded only to learn whether the picture exists
        id: picture
        source: avatar.source
        visible: false
        asynchronous: true
        onStatusChanged: canvas.requestPaint()
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.save()
            ctx.beginPath()
            ctx.arc(width / 2, height / 2, width / 2, 0, 2 * Math.PI)
            ctx.closePath()
            ctx.clip()
            if (avatar.hasPicture) {
                ctx.drawImage(picture, 0, 0, width, height)
            } else {
                const g = ctx.createLinearGradient(0, 0, width, height)
                g.addColorStop(0, "#6c5ce7")
                g.addColorStop(1, "#2b1f5c")
                ctx.fillStyle = g
                ctx.fillRect(0, 0, width, height)
            }
            ctx.restore()
        }
        Component.onCompleted: requestPaint()
    }

    Text {
        anchors.centerIn: parent
        visible: !avatar.hasPicture
        text: avatar.name.length ? avatar.name.charAt(0).toUpperCase() : "?"
        color: "#f4f0ff"
        font.pixelSize: parent.height * 0.42
        font.weight: Font.DemiBold
    }

    Rectangle {  // crisp ring
        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        border.width: 2
        border.color: "#d8ccff"
    }
}
