/* The installer's step list, along the bottom of the window.

   SPDX-FileCopyrightText: 2020 Adriaan de Groot <groot@kde.org>
   SPDX-FileCopyrightText: 2021 Anke Boersma <demm@kaosx.us>
   SPDX-License-Identifier: GPL-3.0-or-later

   Adapted from CachyOS's branding (itself from Calamares' example): the
   Yūrei icon, then one rounded tab per step, the current one in lavender.
*/

import io.calamares.ui 1.0
import io.calamares.core 1.0

import QtQuick
import QtQuick.Layouts

Rectangle {
    id: sideBar
    color: Branding.styleString(Branding.SidebarBackground)
    height: 40  // Calamares sizes the width to its window

    RowLayout {
        anchors.fill: parent
        spacing: 2

        Image {
            id: logo
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.alignment: Qt.AlignCenter
            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            source: "file:/" + Branding.imagePath(Branding.ProductLogo)
            sourceSize.width: 56
            sourceSize.height: 56
            smooth: true
        }

        Repeater {
            model: ViewManager
            Rectangle {
                readonly property bool current: index === ViewManager.currentStepIndex
                Layout.leftMargin: 6
                Layout.rightMargin: 6
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignCenter
                height: 30
                radius: 15
                color: Branding.styleString(current ? Branding.SidebarBackgroundCurrent : Branding.SidebarBackground)

                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    color: Branding.styleString(parent.current ? Branding.SidebarTextCurrent : Branding.SidebarText)
                    text: display
                    elide: Text.ElideRight
                    font.weight: parent.current ? Font.Bold : Font.Normal
                    font.pointSize: parent.current ? 10 : 9
                }
            }
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
