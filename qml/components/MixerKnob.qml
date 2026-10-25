// SPDX-FileCopyrightText: 2026 The Atoll contributors
// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import Atoll

/**
 * A volume knob column for the in-island Cranked Audio mixer card.
 * Shows the knob's custom color, 270° dial ring, level %, source, and action button.
 */
Item {
    id: knobItem

    required property var modelData
    required property int index

    readonly property int level: modelData.level !== undefined ? modelData.level : -1
    readonly property string knobColor: modelData.color || Theme.accent
    readonly property string knobBg: modelData.background || "#000000"
    readonly property bool isMuted: modelData.muted ?? false

    implicitWidth: 68
    implicitHeight: 124

    Column {
        anchors.fill: parent
        spacing: 4

        // Knob Name
        Text {
            width: parent.width
            text: knobItem.modelData.name || ""
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.size(10)
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        // Circular Dial Gauge
        Item {
            id: dialItem
            width: 52
            height: 52
            anchors.horizontalCenter: parent.horizontalCenter

            Canvas {
                id: dialCanvas
                anchors.fill: parent
                antialiasing: true

                property real ratio: Math.max(0, Math.min(1, (knobItem.level >= 0 ? knobItem.level : 0) / 100.0))
                property color fillColor: knobItem.isMuted ? Theme.muted : knobItem.knobColor
                property color trackColor: {
                    const bg = knobItem.knobBg.toLowerCase()
                    if (bg === "#000000" || bg === "#080b10") {
                        return Theme.tint(0.12)
                    }
                    return bg
                }

                onRatioChanged: requestPaint()
                onFillColorChanged: requestPaint()
                onTrackColorChanged: requestPaint()

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()

                    const cx = width / 2
                    const cy = height / 2
                    const radius = width / 2 - 4
                    const startAngle = 0.75 * Math.PI  // 135 deg
                    const totalSweep = 1.5 * Math.PI   // 270 deg

                    ctx.lineWidth = 4
                    ctx.lineCap = "round"

                    // Track
                    ctx.beginPath()
                    ctx.strokeStyle = trackColor
                    ctx.arc(cx, cy, radius, startAngle, startAngle + totalSweep)
                    ctx.stroke()

                    // Level Arc
                    if (ratio > 0.005) {
                        ctx.beginPath()
                        ctx.strokeStyle = fillColor
                        ctx.arc(cx, cy, radius, startAngle, startAngle + totalSweep * ratio)
                        ctx.stroke()
                    }
                }
            }

            // Level text inside the ring
            Text {
                anchors.centerIn: parent
                text: knobItem.isMuted ? qsTr("Mute") : (knobItem.level < 0 ? "–" : (knobItem.level + "%"))
                color: knobItem.isMuted ? Theme.critical : Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.size(knobItem.isMuted ? 9 : 10)
                font.weight: Font.Bold
            }

            // Scroll to change volume
            WheelHandler {
                onWheel: event => {
                    const delta = event.angleDelta.y > 0 ? 3 : -3
                    App.cranked.stepKnob(knobItem.index, delta)
                }
            }

            // Drag to set volume
            MouseArea {
                id: dialArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                function updateFromPoint(mx, my) {
                    const cx = width / 2
                    const cy = height / 2
                    const dx = mx - cx
                    const dy = my - cy
                    let angle = Math.atan2(dy, dx) // -PI to PI
                    // Normalize so startAngle (135 deg = 0.75 PI) is 0
                    let a = angle - 0.75 * Math.PI
                    while (a < 0) a += 2 * Math.PI
                    const sweep = 1.5 * Math.PI
                    if (a > sweep) {
                        // In the dead zone at the bottom: snap to 0 or 100 based on proximity
                        a = (a > sweep + 0.25 * Math.PI) ? 0 : sweep
                    }
                    const pct = Math.round((a / sweep) * 100)
                    App.cranked.setKnob(knobItem.index, pct)
                }

                onPressed: mouse => updateFromPoint(mouse.x, mouse.y)
                onPositionChanged: mouse => {
                    if (pressed) {
                        updateFromPoint(mouse.x, mouse.y)
                    }
                }
            }
        }

        // Source / App Name
        Text {
            width: parent.width
            text: knobItem.isMuted ? qsTr("Muted") : (knobItem.modelData.source || "")
            color: knobItem.modelData.lowered ? Theme.accent : Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.size(9)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        // Button Action Pill
        RoundButton {
            id: actBtn
            anchors.horizontalCenter: parent.horizontalCenter
            width: 26
            height: 26
            visible: knobItem.modelData.press && knobItem.modelData.press !== "Nothing"

            icon: {
                const p = knobItem.modelData.press || ""
                if (p === "Play/Pause") return ["media-playback-pause", "media-playback-start"]
                if (p === "Next") return ["media-skip-forward"]
                if (p === "Previous") return ["media-skip-backward"]
                if (p === "Mute") return ["audio-volume-muted", "audio-volume-high"]
                if (p === "Switch output") return ["audio-card", "audio-speakers"]
                if (p.startsWith("Toggle") || p.startsWith("Turn off")) return ["system-shutdown", "applications-utilities"]
                return ["view-refresh", "go-next"]
            }

            onClicked: App.cranked.press(knobItem.index)
        }
    }
}
