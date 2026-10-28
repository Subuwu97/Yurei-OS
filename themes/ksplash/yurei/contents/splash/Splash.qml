// Yūrei splash for Plasma (ksplashqml), shown while the desktop starts.
//
// It carries on from the boot animation: the same waving loop, scaled and
// placed exactly as the Plymouth theme places it, on the same navy, so the
// hand-over from boot to desktop doesn't jump. A thin bar below follows
// Plasma's start-up stages (ksplashqml sets `stage` from 1 to 6).

import QtQuick
import "wave.js" as Wave

Rectangle {
    id: root
    color: "#060c1f"  // the frames' background, as in the Plymouth theme

    property int stage

    // fit like yurei.script: 92% of the width or 62% of the height, at most 2x
    readonly property real fit: {
        var s = Math.min(width * 0.92 / Wave.frameWidth, height * 0.62 / Wave.frameHeight);
        if (s > 2) s = 2;
        if (s > 0.95 && s < 1.05) s = 1;
        return s;
    }
    property int tick: 0

    Item {
        id: wave
        width: Math.round(Wave.frameWidth * root.fit)
        height: Math.round(Wave.frameHeight * root.fit)
        x: Math.round((root.width - width) / 2)
        y: Math.round((root.height - height) * 0.4)

        // every frame stays loaded, so switching never flickers
        Repeater {
            model: Wave.frameCount
            Image {
                anchors.fill: parent
                source: "images/wave-" + (index < 10 ? "0" : "") + index + ".png"
                smooth: true
                visible: index === Wave.timeline[root.tick]
            }
        }
    }

    // 25 frames per second, as in the boot animation
    Timer {
        interval: 40
        running: true
        repeat: true
        onTriggered: root.tick = (root.tick + 1) % Wave.timeline.length
    }

    Rectangle {
        id: track
        width: Math.round(Math.min(root.width * 0.25, 320))
        height: 3
        radius: 1.5
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.min(wave.y + wave.height + 36, root.height - 48)
        color: "#1d2550"

        Rectangle {
            height: parent.height
            radius: parent.radius
            color: "#b9aaff"
            width: parent.width * Math.max(0, Math.min(root.stage, 6)) / 6
            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        }
    }
}
