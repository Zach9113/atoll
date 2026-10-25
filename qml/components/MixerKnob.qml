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

    property var knob: (typeof modelData !== "undefined" && modelData) ? modelData : {}
    property int knobIndex: (typeof index !== "undefined") ? index : (knob.index !== undefined ? knob.index : 0)

    readonly property string knobName: knob.name || ""
    readonly property int level: (knob.level !== undefined && knob.level !== null) ? Number(knob.level) : -1
    readonly property string knobColor: knob.color || Theme.accent
    readonly property string knobBg: knob.background || "#000000"
    readonly property bool isMuted: Boolean(knob.muted)
    readonly property bool isLowered: Boolean(knob.lowered)
    readonly property string sourceText: knob.source || ""
    readonly property string pressAction: knob.press || ""

    implicitWidth: 64
    implicitHeight: 126

    Column {
        anchors.fill: parent
        spacing: 3

        // Knob Name
        Text {
            width: parent.width
            height: 14
            text: knobItem.knobName
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.size(10)
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
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
                    const bg = (knobItem.knobBg || "").toLowerCase()
                    if (bg === "" || bg === "#000000" || bg === "#080b10") {
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
                    App.cranked.stepKnob(knobItem.knobIndex, delta)
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
                    let angle = Math.atan2(dy, dx)
                    let a = angle - 0.75 * Math.PI
                    while (a < 0) a += 2 * Math.PI
                    const sweep = 1.5 * Math.PI
                    if (a > sweep) {
                        a = (a > sweep + 0.25 * Math.PI) ? 0 : sweep
                    }
                    const pct = Math.round((a / sweep) * 100)
                    App.cranked.setKnob(knobItem.knobIndex, pct)
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
            height: 12
            text: knobItem.isMuted ? qsTr("Muted") : knobItem.sourceText
            color: knobItem.isLowered ? Theme.accent : Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.size(8.5)
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        // Button Action Pill
        Item {
            width: parent.width
            height: 26

            RoundButton {
                anchors.centerIn: parent
                width: 24
                height: 24
                visible: knobItem.pressAction !== "" && knobItem.pressAction !== "Nothing"

                icon: {
                    const p = knobItem.pressAction
                    if (p === "Play/Pause") return ["media-playback-pause", "media-playback-start"]
                    if (p === "Next") return ["media-skip-forward"]
                    if (p === "Previous") return ["media-skip-backward"]
                    if (p === "Mute") return ["audio-volume-muted", "audio-volume-high"]
                    if (p === "Switch output") return ["audio-card", "audio-speakers"]
                    if (p.startsWith("Toggle") || p.startsWith("Turn off")) return ["system-shutdown", "applications-utilities"]
                    return ["view-refresh", "go-next"]
                }

                onClicked: App.cranked.press(knobItem.knobIndex)
            }
        }
    }
}
