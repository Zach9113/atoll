// SPDX-FileCopyrightText: 2026 The Atoll contributors
// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import Atoll

/**
 * A volume knob column for the in-island Cranked Audio mixer card.
 * Shows the knob's custom color, 270° dial ring, level %, source, and action button.
 * Supports mouse wheel scrolling anywhere over the knob, plus click/drag on the dial.
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
    readonly property bool hasAction: pressAction !== "" && pressAction !== "Nothing"
    readonly property bool buttonInside: Boolean(Cfg.get("behavior.mixerButtonInsideKnob", false))

    function getActionIcon(p) {
        if (p === "Play/Pause") return ["media-playback-pause", "media-playback-start"]
        if (p === "Next") return ["media-skip-forward"]
        if (p === "Previous") return ["media-skip-backward"]
        if (p === "Mute") return ["audio-volume-muted", "audio-volume-high"]
        if (p === "Switch output") return ["audio-card", "audio-speakers"]
        if (p.startsWith("Toggle") || p.startsWith("Turn off")) return ["system-shutdown", "applications-utilities"]
        return ["view-refresh", "go-next"]
    }

    implicitWidth: 64
    implicitHeight: 126

    // Wheel scrolling anywhere over this knob column changes volume
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: wheel => {
            const step = Cfg.get("behavior.mixerVolumeStep", 2)
            const delta = (wheel.angleDelta.y > 0 || wheel.angleDelta.x > 0 ? step : -step) * (wheel.modifiers & Qt.ShiftModifier ? 2 : 1)
            App.cranked.stepKnob(knobItem.knobIndex, delta)
            wheel.accepted = true
        }
    }

    Column {
        anchors.fill: parent
        spacing: knobItem.buttonInside ? 4 : 3

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

            // Level text inside the ring (shown when button is NOT inside or channel has no action)
            Text {
                anchors.centerIn: parent
                visible: !knobItem.buttonInside || !knobItem.hasAction
                text: knobItem.isMuted ? qsTr("Mute") : (knobItem.level < 0 ? "–" : (knobItem.level + "%"))
                color: knobItem.isMuted ? Theme.critical : Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.size(knobItem.isMuted ? 9 : 10)
                font.weight: Font.Bold
            }

            // Drag or scroll directly on dial
            MouseArea {
                id: dialArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton

                onWheel: wheel => {
                    const step = Cfg.get("behavior.mixerVolumeStep", 2)
                    const delta = (wheel.angleDelta.y > 0 || wheel.angleDelta.x > 0 ? step : -step) * (wheel.modifiers & Qt.ShiftModifier ? 2 : 1)
                    App.cranked.stepKnob(knobItem.knobIndex, delta)
                    wheel.accepted = true
                }

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

            // Action Button placed directly inside the knob ring
            RoundButton {
                anchors.centerIn: parent
                width: 26
                height: 26
                visible: knobItem.buttonInside && knobItem.hasAction
                icon: knobItem.getActionIcon(knobItem.pressAction)
                onClicked: App.cranked.press(knobItem.knobIndex)
            }
        }

        // Level text below dial (shown when button is inside knob)
        Text {
            width: parent.width
            height: visible ? 13 : 0
            visible: knobItem.buttonInside
            text: knobItem.isMuted ? qsTr("Mute") : (knobItem.level < 0 ? "–" : (knobItem.level + "%"))
            color: knobItem.isMuted ? Theme.critical : Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.size(knobItem.isMuted ? 9 : 10)
            font.weight: Font.Bold
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
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

        // Button Action Pill (shown when button is NOT inside knob)
        Item {
            width: parent.width
            height: visible ? 26 : 0
            visible: !knobItem.buttonInside

            RoundButton {
                anchors.centerIn: parent
                width: 24
                height: 24
                visible: knobItem.hasAction
                icon: knobItem.getActionIcon(knobItem.pressAction)
                onClicked: App.cranked.press(knobItem.knobIndex)
            }
        }
    }
}
