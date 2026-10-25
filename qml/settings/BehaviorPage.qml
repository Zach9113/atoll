// SPDX-FileCopyrightText: 2026 The Atoll contributors
// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import Atoll

SettingsPage {
    title: qsTr("Behaviour")
    description: qsTr("What the pointer does to the island, and how the mixer behaves.")

    SettingsGroup {
        title: qsTr("Pointer actions")

        ChoiceSetting {
            label: qsTr("Click")
            key: "behavior.clickAction"
            defaultValue: "expand"
            options: [
                { value: "expand", label: qsTr("Expand") },
                { value: "none", label: qsTr("Nothing") }
            ]
        }

        ChoiceSetting {
            label: qsTr("Middle click")
            key: "behavior.middleClickAction"
            defaultValue: "playPause"
            options: [
                { value: "playPause", label: qsTr("Play / pause") },
                { value: "mixer", label: qsTr("Open mixer (Cranked Audio)") },
                { value: "none", label: qsTr("Nothing") }
            ]
        }

        ChoiceSetting {
            label: qsTr("Right click")
            key: "behavior.rightClickAction"
            defaultValue: "settings"
            options: [
                { value: "settings", label: qsTr("Open settings") },
                { value: "mixer", label: qsTr("Open mixer (Cranked Audio)") },
                { value: "collapse", label: qsTr("Collapse") },
                { value: "none", label: qsTr("Nothing") }
            ]
        }

        BoolSetting {
            label: qsTr("Scroll changes the volume")
            key: "behavior.scrollAdjustsVolume"
            defaultValue: true
        }

        NumberSetting {
            label: qsTr("Volume step")
            description: qsTr("Volume change per scroll notch on the resting island.")
            key: "behavior.volumeStep"
            defaultValue: 5
            from: 1
            to: 25
            suffix: "%"
            enabled: Cfg.get("behavior.scrollAdjustsVolume", true)
            opacity: enabled ? 1 : 0.45
            last: true
        }
    }

    SettingsGroup {
        title: qsTr("Hover")

        BoolSetting {
            label: qsTr("Peek on hover")
            description: qsTr("Pointing at the island shows what is playing without clicking.")
            key: "behavior.hoverPeek"
            defaultValue: true
        }

        BoolSetting {
            label: qsTr("Expand on hover")
            description: qsTr("Unfolds the whole dashboard when the pointer rests on the island.")
            key: "behavior.expandOnHover"
            defaultValue: false
        }

        NumberSetting {
            label: qsTr("Hover delay")
            key: "behavior.hoverDelay"
            defaultValue: 180
            from: 0
            to: 2000
            step: 10
            suffix: " ms"
        }

        BoolSetting {
            label: qsTr("Collapse when the pointer leaves")
            key: "behavior.collapseOnLeave"
            defaultValue: true
            last: true
        }
    }

    SettingsGroup {
        title: qsTr("Mixer (Cranked Audio)")

        ChoiceSetting {
            label: qsTr("Layout style")
            description: qsTr("Visual layout for the Cranked Audio mixer card inside the island.")
            key: "behavior.mixerStyle"
            defaultValue: "knobs"
            options: [
                { value: "knobs", label: qsTr("Knobs (circular dials)") },
                { value: "faders", label: qsTr("Faders (mixing desk)") },
                { value: "sliders", label: qsTr("Sliders (horizontal bars)") }
            ]
        }

        BoolSetting {
            label: qsTr("Keep mixer open in island")
            description: qsTr("Automatically opens the mixer card whenever the island expands, without needing to click the Mixer pill.")
            key: "behavior.mixerExpanded"
            defaultValue: false
        }

        BoolSetting {
            label: qsTr("Button inside knob")
            description: qsTr("In Knobs style, place the channel action button directly inside the circular dial ring.")
            key: "behavior.mixerButtonInsideKnob"
            defaultValue: false
            enabled: Cfg.get("behavior.mixerStyle", "knobs") === "knobs"
            opacity: enabled ? 1 : 0.45
        }

        NumberSetting {
            label: qsTr("Mixer scroll step")
            description: qsTr("Volume change per scroll notch on mixer controls.")
            key: "behavior.mixerVolumeStep"
            defaultValue: 2
            from: 1
            to: 25
            suffix: "%"
        }

        BoolSetting {
            label: qsTr("Show channel names")
            description: qsTr("Display channel labels (e.g. Media, Music, Game).")
            key: "behavior.mixerShowNames"
            defaultValue: true
        }

        BoolSetting {
            label: qsTr("Show percentages")
            description: qsTr("Display numeric volume percentage text.")
            key: "behavior.mixerShowPercent"
            defaultValue: true
        }

        BoolSetting {
            label: qsTr("Show what is playing")
            description: qsTr("Display the active application or source below each channel.")
            key: "behavior.mixerShowSource"
            defaultValue: true
        }

        BoolSetting {
            label: qsTr("Show action buttons")
            description: qsTr("Display action buttons (Play/Pause, Mute, Next).")
            key: "behavior.mixerShowButtons"
            defaultValue: true
            last: true
        }
    }
}
