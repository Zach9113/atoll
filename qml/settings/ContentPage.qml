// SPDX-FileCopyrightText: 2026 The Atoll contributors
// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import Atoll

SettingsPage {
    title: qsTr("What shows")
    description: qsTr("What the resting island shows, and which features the island has at all.")

    SettingsGroup {
        title: qsTr("Resting island")

        ChoiceSetting {
            label: qsTr("Resting state")
            description: qsTr("\"Auto\" shows the clock, the cover of whatever is playing, and a dot for anything waiting.")
            key: "island.idleMode"
            defaultValue: "auto"
            options: [
                { value: "auto", label: qsTr("Auto") },
                { value: "clock", label: qsTr("Clock") },
                { value: "notch", label: qsTr("Bare notch") },
                { value: "hidden", label: qsTr("Hidden") }
            ]
        }

        BoolSetting {
            label: qsTr("Always show something")
            description: qsTr("Keeps the island on screen even in \"hidden\" mode, so there is always somewhere to click.")
            key: "island.alwaysVisible"
            defaultValue: true
            last: true
        }
    }

    SettingsGroup {
        title: qsTr("In the resting island")

        BoolSetting {
            label: qsTr("Clock")
            key: "idle.showClock"
            defaultValue: true
            // Greyed out while the whole feature is off under Features.
            enabled: Cfg.get("modules.clock", true)
            opacity: enabled ? 1 : 0.45
        }

        BoolSetting {
            label: qsTr("Day and date")
            description: qsTr("The date next to the time, in the format set further down this page.")
            key: "idle.showDate"
            defaultValue: false
            enabled: Cfg.get("modules.clock", true)
            opacity: enabled ? 1 : 0.45
        }

        BoolSetting {
            label: qsTr("Cover of what is playing")
            description: qsTr("A small cover next to the clock while music plays.")
            key: "idle.showMediaBadge"
            alsoKeys: ["media.idleBadge"]
            defaultValue: true
            enabled: Cfg.get("modules.media", true)
            opacity: enabled ? 1 : 0.45
        }

        BoolSetting {
            label: qsTr("Notification dot")
            description: qsTr("The pulsing accent dot while notifications are waiting.")
            key: "idle.showNotificationDot"
            defaultValue: true
            enabled: Cfg.get("modules.notifications", true)
            opacity: enabled ? 1 : 0.45
        }

        BoolSetting {
            label: qsTr("Low battery dot")
            key: "idle.showBatteryDot"
            defaultValue: true
            enabled: Cfg.get("modules.battery", true)
            opacity: enabled ? 1 : 0.45
        }

        BoolSetting {
            label: qsTr("Privacy indicators")
            description: qsTr("One dot, blended orange, red and violet while an application is using the microphone, the camera or your screen.")
            key: "idle.showPrivacyIndicators"
            defaultValue: true
            enabled: Cfg.get("modules.privacy", true)
            opacity: enabled ? 1 : 0.45
        }

        BoolSetting {
            label: qsTr("Next calendar event")
            description: qsTr("The next event from your calendars, when one is coming up soon.")
            key: "idle.showCalendarHint"
            alsoKeys: ["calendar.showInIdle"]
            defaultValue: true
            enabled: Cfg.get("modules.calendar", true)
            opacity: enabled ? 1 : 0.45
            last: true
        }
    }

    SettingsGroup {
        title: qsTr("Clock")

        TextSetting {
            label: qsTr("Time format")
            description: qsTr("Qt date format, e.g. HH:mm or h:mm ap.")
            key: "clock.timeFormat"
            defaultValue: "HH:mm"
            placeholder: "HH:mm"
        }

        TextSetting {
            label: qsTr("Date format")
            key: "clock.dateFormat"
            defaultValue: "ddd d MMM"
            placeholder: "ddd d MMM"
            last: true
        }
    }

    SettingsGroup {
        title: qsTr("Features")

        BoolSetting {
            label: qsTr("Volume and brightness")
            description: qsTr("Mirrors Plasma's own OSD.")
            key: "modules.osd"
            defaultValue: true
        }

        BoolSetting {
            label: qsTr("Notifications")
            description: qsTr("Mirrors your notification daemon; it does not replace it.")
            key: "modules.notifications"
            defaultValue: true
        }

        BoolSetting {
            label: qsTr("Media")
            key: "modules.media"
            defaultValue: true
        }

        BoolSetting {
            label: qsTr("Lyrics")
            key: "modules.lyrics"
            defaultValue: true
        }

        BoolSetting {
            label: qsTr("Spectrum")
            description: qsTr("Needs cava to show a real spectrum; without it the bars are decorative.")
            key: "modules.visualizer"
            defaultValue: true
        }

        BoolSetting {
            label: qsTr("Clock")
            key: "modules.clock"
            defaultValue: true
        }

        BoolSetting {
            label: qsTr("Calendar")
            description: qsTr("Upcoming events in the dashboard and resting island.")
            key: "modules.calendar"
            defaultValue: true
        }

        BoolSetting {
            label: qsTr("Battery")
            key: "modules.battery"
            defaultValue: true
        }

        BoolSetting {
            label: qsTr("Bluetooth")
            description: qsTr("Adapter power and device connections, managed from the dashboard.")
            key: "modules.bluetooth"
            defaultValue: true
        }

        BoolSetting {
            label: qsTr("Bluetooth device panel")
            description: qsTr("Adds a collapsible panel of paired devices to the dashboard; click its header to fold or unfold it.")
            key: "bluetooth.showInExpanded"
            defaultValue: false
            enabled: Cfg.get("modules.bluetooth", true)
            opacity: enabled ? 1 : 0.45
        }

        BoolSetting {
            label: qsTr("Privacy indicators")
            description: qsTr("Watches PipeWire for camera, microphone and screen capture. Without it the dots never light.")
            key: "modules.privacy"
            defaultValue: true
        }

        BoolSetting {
            label: qsTr("Sharing")
            description: qsTr("Files dropped on the island, and files offered by nearby devices.")
            key: "modules.sharing"
            defaultValue: true
            last: true
        }
    }

    SettingsGroup {
        title: qsTr("Volume and brightness")

        NumberSetting {
            label: qsTr("On screen for")
            key: "osd.timeout"
            defaultValue: 1700
            from: 300
            to: 10000
            step: 100
            suffix: " ms"
        }

        BoolSetting {
            label: qsTr("Include media player volume")
            key: "osd.showMediaPlayerVolume"
            defaultValue: true
            last: true
        }
    }
}
