// SPDX-FileCopyrightText: 2026 The Atoll contributors
// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import Atoll

/** A circular icon button sized for transport controls. */
Item {
    id: button

    property alias icon: glyph.names
    property real iconScale: 0.52
    property color tint: Theme.foreground
    property string tooltip: ""
    property bool tipAbove: false
    property string tipAlign: "center"   // "center", "left" or "right"

    signal clicked()

    implicitWidth: 30
    implicitHeight: 30
    opacity: enabled ? (mouse.containsMouse ? 1.0 : 0.86) : 0.32

    Behavior on opacity {
        NumberAnimation {
            duration: Theme.fast
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent"

        Behavior on color {
            ColorAnimation {
                duration: Theme.fast
            }
        }
    }

    Ripple {
        anchors.fill: parent
        pressed: mouse.pressed
        cornerRadius: width / 2
    }

    IconImage {
        id: glyph
        anchors.centerIn: parent
        width: Math.round(parent.width * button.iconScale)
        height: width
    }

    scale: mouse.pressed ? 0.9 : 1.0

    Behavior on scale {
        NumberAnimation {
            duration: Theme.fast
            easing.type: Easing.OutBack
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
        onPositionChanged: if (tip.visible) tip.updatePosition()
    }

    // Hover tooltip (set `tooltip` to enable)
    Timer {
        id: tipDelay
        interval: 450
        running: button.tooltip.length > 0 && button.visible && mouse.containsMouse && !mouse.pressed
    }

    Rectangle {
        id: tip
        visible: button.tooltip.length > 0 && button.visible && mouse.containsMouse && !tipDelay.running && !mouse.pressed
        enabled: false
        z: 99999
        width: tipText.implicitWidth + 14
        height: tipText.implicitHeight + 8
        radius: 6
        color: Qt.rgba(0.12, 0.12, 0.15, 1.0)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.15)

        property Item targetParent: null

        function updatePosition() {
            if (!targetParent) {
                let cur = button.parent
                let topItem = null
                while (cur) {
                    if (cur.isViewRoot) {
                        topItem = cur
                        break
                    }
                    topItem = cur
                    cur = cur.parent
                }
                if (topItem) {
                    targetParent = topItem
                    tip.parent = topItem
                }
            }

            let root = targetParent || button
            let pt = button.mapToItem(root, 0, 0)

            let desiredX = pt.x + (button.tipAlign === "right" ? button.width - tip.width
                                 : button.tipAlign === "left" ? 0
                                 : (button.width - tip.width) / 2)
            tip.x = Math.max(12, Math.min(root.width - tip.width - 12, desiredX))

            let desiredY
            if (button.tipAbove) {
                desiredY = pt.y - tip.height - 6
                if (desiredY < 10) {
                    desiredY = pt.y + button.height + 6
                }
            } else {
                desiredY = pt.y + button.height + 6
                if (desiredY + tip.height > root.height - 10) {
                    desiredY = pt.y - tip.height - 6
                }
            }
            tip.y = Math.max(10, Math.min(root.height - tip.height - 10, desiredY))
        }

        onVisibleChanged: {
            if (visible) {
                updatePosition()
            }
        }

        Text {
            id: tipText
            anchors.centerIn: parent
            text: button.tooltip
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.size(9.5)
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
