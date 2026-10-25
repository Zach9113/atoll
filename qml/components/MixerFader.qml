// SPDX-FileCopyrightText: 2026 The Atoll contributors
// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import Atoll

/**
 * A vertical studio mixing-desk fader column for the in-island Cranked Audio mixer card.
 * Shows the channel name, a tactile vertical fader track & cap, level %, source, and action button.
 */
Item {
    id: faderItem

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
    readonly property bool showNames: Boolean(Cfg.get("behavior.mixerShowNames", true))
    readonly property bool showPercent: Boolean(Cfg.get("behavior.mixerShowPercent", true))
    readonly property bool showSource: Boolean(Cfg.get("behavior.mixerShowSource", true))
    readonly property bool showButtons: Boolean(Cfg.get("behavior.mixerShowButtons", true))

    readonly property real ratio: Math.max(0, Math.min(1, (level >= 0 ? level : 0) / 100.0))

    implicitWidth: 64
    implicitHeight: 126

    // Wheel scrolling anywhere over this fader column changes volume
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: wheel => {
            const step = Cfg.get("behavior.mixerVolumeStep", 2)
            const delta = (wheel.angleDelta.y > 0 || wheel.angleDelta.x > 0 ? step : -step) * (wheel.modifiers & Qt.ShiftModifier ? 2 : 1)
            App.cranked.stepKnob(faderItem.knobIndex, delta)
            wheel.accepted = true
        }
    }

    Column {
        anchors.fill: parent
        spacing: 3

        // Channel Name
        Text {
            width: parent.width
            height: visible ? 14 : 0
            visible: faderItem.showNames
            text: faderItem.knobName
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.size(10)
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        // Vertical Fader Slot & Cap
        Item {
            id: faderArea
            width: 44
            height: 52
            anchors.horizontalCenter: parent.horizontalCenter

            // Track slot background
            Rectangle {
                id: trackSlot
                width: 6
                height: parent.height
                radius: 3
                anchors.horizontalCenter: parent.horizontalCenter
                color: {
                    const bg = (faderItem.knobBg || "").toLowerCase()
                    if (bg === "" || bg === "#000000" || bg === "#080b10") {
                        return Theme.tint(0.12)
                    }
                    return bg
                }

                // Level fill bar from bottom up
                Rectangle {
                    width: parent.width
                    height: Math.max(0, Math.min(parent.height, parent.height * faderItem.ratio))
                    anchors.bottom: parent.bottom
                    radius: 3
                    color: faderItem.isMuted ? Theme.muted : faderItem.knobColor
                }
            }

            // Fader Cap Thumb
            Rectangle {
                id: faderCap
                width: 32
                height: 14
                radius: 3
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.round((1.0 - faderItem.ratio) * (faderArea.height - height))

                color: Theme.tint(0.22)

                // Grip indicator line in knob color
                Rectangle {
                    anchors.centerIn: parent
                    width: 16
                    height: 2
                    radius: 1
                    color: faderItem.isMuted ? Theme.muted : faderItem.knobColor
                }
            }

            // Drag mouse area for fader thumb
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton

                function updateFromY(my) {
                    const usableHeight = faderArea.height - faderCap.height
                    if (usableHeight <= 0) return
                    const clampedY = Math.max(0, Math.min(usableHeight, my - faderCap.height / 2))
                    const pct = Math.round((1.0 - (clampedY / usableHeight)) * 100)
                    App.cranked.setKnob(faderItem.knobIndex, pct)
                }

                onPressed: mouse => updateFromY(mouse.y)
                onPositionChanged: mouse => {
                    if (pressed) {
                        updateFromY(mouse.y)
                    }
                }

                onWheel: wheel => {
                    const step = Cfg.get("behavior.mixerVolumeStep", 2)
                    const delta = (wheel.angleDelta.y > 0 || wheel.angleDelta.x > 0 ? step : -step) * (wheel.modifiers & Qt.ShiftModifier ? 2 : 1)
                    App.cranked.stepKnob(faderItem.knobIndex, delta)
                    wheel.accepted = true
                }
            }
        }

        // Level text
        Text {
            width: parent.width
            height: visible ? 12 : 0
            visible: faderItem.showPercent
            text: faderItem.isMuted ? qsTr("Mute") : (faderItem.level < 0 ? "–" : (faderItem.level + "%"))
            color: faderItem.isMuted ? Theme.critical : Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.size(faderItem.isMuted ? 9 : 10)
            font.weight: Font.Bold
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        // Source / App Name
        Text {
            width: parent.width
            height: visible ? 12 : 0
            visible: faderItem.showSource
            text: faderItem.isMuted ? qsTr("Muted") : faderItem.sourceText
            color: faderItem.isLowered ? Theme.accent : Theme.muted
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
            height: visible ? 26 : 0
            visible: faderItem.showButtons

            RoundButton {
                anchors.centerIn: parent
                width: 24
                height: 24
                visible: faderItem.pressAction !== "" && faderItem.pressAction !== "Nothing"

                icon: {
                    const p = faderItem.pressAction
                    if (p === "Play/Pause") return ["media-playback-pause", "media-playback-start"]
                    if (p === "Next") return ["media-skip-forward"]
                    if (p === "Previous") return ["media-skip-backward"]
                    if (p === "Mute") return ["audio-volume-muted", "audio-volume-high"]
                    if (p === "Switch output") return ["audio-card", "audio-speakers"]
                    if (p.startsWith("Toggle") || p.startsWith("Turn off")) return ["system-shutdown", "applications-utilities"]
                    return ["view-refresh", "go-next"]
                }

                onClicked: App.cranked.press(faderItem.knobIndex)
            }
        }
    }
}
