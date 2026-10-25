// SPDX-FileCopyrightText: 2026 The Atoll contributors
// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import Atoll

// Grouped and worded like the Look settings in Cranked Audio's own window and
// panel widget, so the same option has the same name in all three places.
SettingsPage {
    title: qsTr("Mixer")
    description: qsTr("The Cranked Audio mixer card that the Mixer button opens in the dashboard.")

    SettingsGroup {
        title: qsTr("Look")

        ChoiceSetting {
            label: qsTr("Style")
            key: "behavior.mixerStyle"
            defaultValue: "knobs"
            options: [
                { value: "knobs", label: qsTr("Knobs (dials)") },
                { value: "sliders", label: qsTr("Sliders (compact list)") },
                { value: "faders", label: qsTr("Faders (like a mixing desk)") }
            ]
        }

        BoolSetting {
            label: qsTr("Knob names")
            key: "behavior.mixerShowNames"
            defaultValue: true
        }

        BoolSetting {
            label: qsTr("Percentages")
            key: "behavior.mixerShowPercent"
            defaultValue: true
        }

        BoolSetting {
            label: qsTr("What's playing")
            description: qsTr("The app playing on each knob right now.")
            key: "behavior.mixerShowSource"
            defaultValue: true
            last: true
        }
    }

    SettingsGroup {
        title: qsTr("Buttons")

        BoolSetting {
            label: qsTr("Show the buttons")
            description: qsTr("Each knob's button: play/pause, mute, next and whatever else it is set to in Cranked Audio.")
            key: "behavior.mixerShowButtons"
            defaultValue: true
        }

        BoolSetting {
            label: qsTr("Inside the dials")
            description: qsTr("Puts the button in the middle of the dial, which takes less room. Knobs style only.")
            key: "behavior.mixerButtonInsideKnob"
            defaultValue: false
            enabled: Cfg.get("behavior.mixerStyle", "knobs") === "knobs"
                     && Cfg.get("behavior.mixerShowButtons", true)
            opacity: enabled ? 1 : 0.45
            last: true
        }
    }

    SettingsGroup {
        title: qsTr("In the island")

        BoolSetting {
            label: qsTr("Open with the dashboard")
            description: qsTr("Shows the mixer every time the island expands, without clicking the Mixer button.")
            key: "behavior.mixerExpanded"
            defaultValue: false
        }

        NumberSetting {
            label: qsTr("Scroll step")
            description: qsTr("How far one notch of the scroll wheel turns a knob.")
            key: "behavior.mixerVolumeStep"
            defaultValue: 2
            from: 1
            to: 25
            suffix: "%"
            last: true
        }
    }
}
