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
    readonly property bool hasAction: pressAction !== "" && pressAction !== "Nothing"
    readonly property bool showNames: Boolean(Cfg.get("behavior.mixerShowNames", true))
    readonly property bool showPercent: Boolean(Cfg.get("behavior.mixerShowPercent", true))
    readonly property bool showSource: Boolean(Cfg.get("behavior.mixerShowSource", true))
    readonly property bool showButtons: Boolean(Cfg.get("behavior.mixerShowButtons", true))

    readonly property real ratio: Math.max(0, Math.min(1, (level >= 0 ? level : 0) / 100.0))

    implicitWidth: parent ? parent.width : 380
    implicitHeight: 34

    // Left Color Bar
    Rectangle {
        id: colorBar
        anchors.left: parent.left
        anchors.leftMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        width: 4
        height: 22
        radius: 2
        color: sliderItem.isMuted ? Theme.muted : sliderItem.knobColor
    }

    // Channel Name & Source
    Column {
        id: labelCol
        anchors.left: colorBar.right
        anchors.leftMargin: (sliderItem.showNames || sliderItem.showSource) ? 10 : 2
        anchors.verticalCenter: parent.verticalCenter
        width: (sliderItem.showNames || sliderItem.showSource) ? 95 : 0
        visible: sliderItem.showNames || sliderItem.showSource
        spacing: 2

        Text {
            width: parent.width
            visible: sliderItem.showNames
            text: sliderItem.knobName
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.size(11)
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        Text {
            width: parent.width
            visible: sliderItem.showSource
            text: sliderItem.isMuted ? qsTr("Muted") : (sliderItem.sourceText || qsTr("Idle"))
            color: sliderItem.isLowered ? Theme.accent : Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.size(9)
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }

    // Action Button (on the far right)
    Item {
        id: actionBtnItem
        anchors.right: parent.right
        anchors.rightMargin: (sliderItem.showButtons && sliderItem.hasAction) ? 6 : 0
        anchors.verticalCenter: parent.verticalCenter
        width: (sliderItem.showButtons && sliderItem.hasAction) ? 26 : 0
        height: 26
        visible: sliderItem.showButtons && sliderItem.hasAction

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

    // Percentage Text (to the left of action button)
    Text {
        id: pctLabel
        anchors.right: actionBtnItem.left
        anchors.rightMargin: (sliderItem.showButtons && sliderItem.hasAction) ? 8 : 4
        anchors.verticalCenter: parent.verticalCenter
        width: sliderItem.showPercent ? 36 : 0
        visible: sliderItem.showPercent
        horizontalAlignment: Text.AlignRight
        text: sliderItem.isMuted ? qsTr("Mute") : (sliderItem.level < 0 ? "–" : (sliderItem.level + "%"))
        color: sliderItem.isMuted ? Theme.critical : Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.size(10)
        font.weight: Font.DemiBold
    }

    // Horizontal Slider Track (stretches dynamically between labelCol and pctLabel)
    Item {
        id: trackContainer
        anchors.left: (sliderItem.showNames || sliderItem.showSource) ? labelCol.right : colorBar.right
        anchors.leftMargin: 12
        anchors.right: pctLabel.visible ? pctLabel.left : (actionBtnItem.visible ? actionBtnItem.left : parent.right)
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        height: 24

        // Groove Background
        Rectangle {
            id: groove
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 6
            radius: 3
            color: Theme.tint(0.12)

            // Filled portion
            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Math.max(0, Math.min(parent.width, parent.width * sliderItem.ratio))
                radius: 3
                color: sliderItem.isMuted ? Theme.muted : sliderItem.knobColor
            }
        }

        // Thumb / Knob Handle
        Rectangle {
            id: thumb
            width: 14
            height: 14
            radius: 7
            anchors.verticalCenter: parent.verticalCenter
            x: Math.max(0, Math.min(trackContainer.width - width, Math.round(trackContainer.width * sliderItem.ratio - width / 2)))
            color: Theme.foreground
            border.width: 1
            border.color: Theme.tint(0.3)
        }

        // Interactive Drag / Click / Wheel Area
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

    // Wheel scrolling over the entire row
    MouseArea {
        anchors.fill: parent
        z: -1
        acceptedButtons: Qt.NoButton
        onWheel: wheel => {
            const step = Cfg.get("behavior.mixerVolumeStep", 2)
            const delta = (wheel.angleDelta.y > 0 || wheel.angleDelta.x > 0 ? step : -step) * (wheel.modifiers & Qt.ShiftModifier ? 2 : 1)
            App.cranked.stepKnob(sliderItem.knobIndex, delta)
            wheel.accepted = true
        }
    }
}
