/* Slides shown while Yūrei installs.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Backgrounds are made from the Yūrei artwork by branding/build-assets.py;
 * the text is drawn here so it stays sharp at any window size.
 */

import QtQuick
import calamares.slideshow 1.0

Presentation {
    id: presentation

    // a background picture, darkened on the left where the text sits
    component YureiSlide: Slide {
        id: slide
        property string art
        property string heading
        property string body
        anchors.fill: parent

        Image {
            anchors.fill: parent
            source: slide.art
            fillMode: Image.PreserveAspectCrop
            horizontalAlignment: Image.AlignRight
            smooth: true
        }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "#e6060c1f" }
                GradientStop { position: 0.45; color: "#b3060c1f" }
                GradientStop { position: 0.75; color: "#00060c1f" }
            }
        }
        Column {
            x: Math.round(parent.width * 0.05)
            width: Math.round(parent.width * 0.42)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Math.round(slide.height * 0.035)

            Text {
                width: parent.width
                text: slide.heading
                color: "#f1e9ff"
                font.pixelSize: Math.max(18, Math.round(slide.height * 0.075))
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
            }
            Rectangle {
                width: Math.round(slide.height * 0.12)
                height: 3
                radius: 1.5
                color: "#b9aaff"
            }
            Text {
                width: parent.width
                text: slide.body
                color: "#e6e1ff"
                font.pixelSize: Math.max(13, Math.round(slide.height * 0.042))
                lineHeight: 1.25
                wrapMode: Text.WordWrap
                textFormat: Text.StyledText
            }
        }
    }

    function nextSlide() {
        presentation.goToNextSlide();
    }

    Timer {
        id: advanceTimer
        interval: 20000
        running: presentation.activatedInCalamares
        repeat: true
        onTriggered: nextSlide()
    }

    YureiSlide {
        art: "slide-shrine.jpg"
        heading: qsTr("Welcome to Yūrei")
        body: qsTr("Your new system is being installed. Yūrei is a gaming-first desktop built on CachyOS, and ready for everything else too.")
    }

    YureiSlide {
        art: "slide-moon.jpg"
        heading: qsTr("Ready to play")
        body: qsTr("Steam, Proton, Lutris, Heroic, GameMode, MangoHud and gamescope come installed and tuned. <b>Right Shift + F12</b> shows the performance overlay in games.")
    }

    YureiSlide {
        art: "slide-wave.jpg"
        heading: qsTr("Steam Game Mode")
        body: qsTr("Choose <b>Steam Game Mode (Yūrei)</b> at the login screen for full-screen, console-style Steam. <b>Switch to Desktop</b> in Steam's power menu brings you back.")
    }

    YureiSlide {
        art: "slide-shrine.jpg"
        heading: qsTr("Make it yours")
        body: qsTr("Add whole sets of apps in one go: <b>yurei install streaming emulation creative</b>. Run <b>yurei bundles</b> to see them all.")
    }

    YureiSlide {
        art: "slide-moon.jpg"
        heading: qsTr("Keeps itself in shape")
        body: qsTr("<b>yurei update</b> updates everything, Flatpaks and the AUR included. <b>yurei doctor --fix</b> checks and repairs what games need.")
    }

    // Calamares (slideshow API 2) calls these when the slides appear and leave
    function onActivate() {
        presentation.currentSlide = 0;
    }

    function onLeave() {
    }
}
