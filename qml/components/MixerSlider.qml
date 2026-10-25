// SPDX-FileCopyrightText: 2026 The Atoll contributors
// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import Atoll

/**
 * A horizontal volume slider row for the in-island Cranked Audio mixer card.
 * Shows color indicator bar, channel/source labels, horizontal progress slider bar,
 * percentage text, and action button.
 */
Item {
    id: sliderItem

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

    readonly property real ratio: Math.max(0, Math.min(1, (level >= 0 ? level : 0) / 100.0))

    implicitWidth: parent ? parent.width : 380
    implicitHeight: 32

    // Wheel scrolling anywhere over this row changes volume
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: wheel => {
            const step = Cfg.get("behavior.mixerVolumeStep", 2)
            const delta = (wheel.angleDelta.y > 0 || wheel.angleDelta.x > 0 ? step : -step) * (wheel.modifiers & Qt.ShiftModifier ? 2 : 1)
            App.cranked.stepKnob(sliderItem.knobIndex, delta)
            wheel.accepted = true
        }
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.rightMargin: 4
        spacing: 8

        // Left Color Bar
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 4
            height: 20
            radius: 2
            color: sliderItem.isMuted ? Theme.muted : sliderItem.knobColor
        }

        // Channel Name & Source
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: 85
            spacing: 1

            Text {
                width: parent.width
                text: sliderItem.knobName
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.size(10.5)
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                width: parent.width
                text: sliderItem.isMuted ? qsTr("Muted") : (sliderItem.sourceText || qsTr("Idle"))
                color: sliderItem.isLowered ? Theme.accent : Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.size(8.5)
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }

        // Horizontal Slider Bar Track
        Item {
            id: trackContainer
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(80, parent.width - 4 - 85 - 34 - (hasAction ? 28 : 0) - (parent.spacing * 4))
            height: 20

            // Background Groove
            Rectangle {
                id: groove
                anchors.centerIn: parent
                width: parent.width
                height: 6
                radius: 3
                color: Theme.tint(0.12)

                // Filled portion
                Rectangle {
                    width: Math.max(0, Math.min(parent.width, parent.width * sliderItem.ratio))
                    height: parent.height
                    radius: 3
                    color: sliderItem.isMuted ? Theme.muted : sliderItem.knobColor
                }
            }

            // Slider Thumb
            Rectangle {
                width: 14
                height: 14
                radius: 7
                anchors.verticalCenter: parent.verticalCenter
                x: Math.max(0, Math.min(trackContainer.width - width, Math.round(trackContainer.width * sliderItem.ratio - width / 2)))

                color: Theme.foreground
                border.width: 1
                border.color: Theme.tint(0.3)
            }

            // Interactive Drag Area
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton

                function updateFromX(mx) {
                    if (trackContainer.width <= 0) return
                    const clampedX = Math.max(0, Math.min(trackContainer.width, mx))
                    const pct = Math.round((clampedX / trackContainer.width) * 100)
                    App.cranked.setKnob(sliderItem.knobIndex, pct)
                }

                onPressed: mouse => updateFromX(mouse.x)
                onPositionChanged: mouse => {
                    if (pressed) {
                        updateFromX(mouse.x)
                    }
                }

                onWheel: wheel => {
                    const step = Cfg.get("behavior.mixerVolumeStep", 2)
                    const delta = (wheel.angleDelta.y > 0 || wheel.angleDelta.x > 0 ? step : -step) * (wheel.modifiers & Qt.ShiftModifier ? 2 : 1)
                    App.cranked.stepKnob(sliderItem.knobIndex, delta)
                    wheel.accepted = true
                }
            }
        }

        // Percentage Text
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 32
            horizontalAlignment: Text.AlignRight
            text: sliderItem.isMuted ? qsTr("Mute") : (sliderItem.level < 0 ? "–" : (sliderItem.level + "%"))
            color: sliderItem.isMuted ? Theme.critical : Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.size(9.5)
            font.weight: Font.Bold
        }

        // Action Button
        readonly property bool hasAction: sliderItem.pressAction !== "" && sliderItem.pressAction !== "Nothing"
        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: 24
            height: 24
            visible: parent.hasAction

            RoundButton {
                anchors.fill: parent

                icon: {
                    const p = sliderItem.pressAction
                    if (p === "Play/Pause") return ["media-playback-pause", "media-playback-start"]
                    if (p === "Next") return ["media-skip-forward"]
                    if (p === "Previous") return ["media-skip-backward"]
                    if (p === "Mute") return ["audio-volume-muted", "audio-volume-high"]
                    if (p === "Switch output") return ["audio-card", "audio-speakers"]
                    if (p.startsWith("Toggle") || p.startsWith("Turn off")) return ["system-shutdown", "applications-utilities"]
                    return ["view-refresh", "go-next"]
                }

                onClicked: App.cranked.press(sliderItem.knobIndex)
            }
        }
    }
}
