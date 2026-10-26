// SPDX-FileCopyrightText: 2026 The Atoll contributors
// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import Atoll

SettingsPage {
    id: page

    title: qsTr("About")
    description: qsTr("Atoll %1 - a dynamic island for KDE Plasma.").arg(App.version)

    property bool confirmingReset: false
    property bool islandUp: App.islandRunning()

    Component.onCompleted: {
        if (App.updater.state === "idle" && Cfg.get("updates.check", true))
            App.updater.check()
    }

    SettingsGroup {
        title: qsTr("Status")

        SettingRow {
            label: qsTr("Islands")
            description: App.shell.targets.length > 0
                         ? App.shell.targets.join(", ")
                         : qsTr("No output matches the current selection.")
        }

        SettingRow {
            label: qsTr("Island process")
            description: page.islandUp
                         ? qsTr("Running. Every change on this page reaches it as you make it.")
                         : qsTr("Not running, so nothing is showing your settings yet.")
            last: true

            PushButton {
                text: page.islandUp ? qsTr("Restart") : qsTr("Start")
                onClicked: {
                    App.startIsland()
                    page.islandUp = true
                }
            }
        }
    }

    SettingsGroup {
        title: qsTr("Updates")

        SettingRow {
            label: qsTr("Atoll %1").arg(App.version)
            description: {
                const updater = App.updater
                if (updater.state === "idle")
                    return updater.canInstall
                           ? qsTr("Updates come from the releases on github.com/Zach9113/atoll.")
                           : qsTr("This copy was not installed as the atoll-git package, so updating only opens the release page.")
                return updater.message
            }

            PushButton {
                text: App.updater.state === "available"
                      ? (App.updater.canInstall ? qsTr("Update to %1").arg(App.updater.latestVersion) : qsTr("See release"))
                      : App.updater.busy ? qsTr("Working…") : qsTr("Check now")
                enabled: !App.updater.busy
                opacity: enabled ? 1 : 0.45
                onClicked: {
                    if (App.updater.state === "available")
                        App.updater.install()
                    else
                        App.updater.check()
                }
            }
        }

        // How far an update has got, so a build that takes a while does not look stuck.
        Item {
            width: parent.width
            height: 14
            visible: App.updater.percent >= 0

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                height: 6
                radius: 3
                color: Skin.line

                Rectangle {
                    width: parent.width * Math.max(0, App.updater.percent) / 100
                    height: parent.height
                    radius: parent.radius
                    color: Skin.accent

                    Behavior on width {
                        NumberAnimation {
                            duration: 250
                        }
                    }
                }
            }
        }

        BoolSetting {
            label: qsTr("Check for updates")
            description: qsTr("Two minutes after Atoll starts and every six hours. It only asks GitHub for the latest release.")
            key: "updates.check"
            defaultValue: true
            last: true
        }
    }

    SettingsGroup {
        title: qsTr("Configuration")

        SettingRow {
            label: qsTr("Config file")
            description: App.config.path

            PushButton {
                text: qsTr("Open")
                onClicked: App.openUrl("file://" + App.config.path)
            }
        }

        SettingRow {
            label: qsTr("Reset everything")
            description: qsTr("Puts every setting back to how Atoll ships.")
            last: true

            PushButton {
                text: page.confirmingReset ? qsTr("Really reset?") : qsTr("Reset")
                destructive: true
                onClicked: {
                    if (page.confirmingReset) {
                        App.config.resetAll()
                        page.confirmingReset = false
                        confirmTimeout.stop()
                    } else {
                        page.confirmingReset = true
                        confirmTimeout.restart()
                    }
                }
            }
        }
    }

    SettingsGroup {
        title: qsTr("Scripting")

        SettingRow {
            label: qsTr("D-Bus")
            description: "org.atoll.Atoll on /Atoll - expand, collapse, toggle, showText, showProgress, share, settings, reloadConfig, quit."
        }

        SettingRow {
            label: qsTr("Command line")
            description: "atollctl text drive-harddisk \"Backup finished\"\natollctl progress cloud-upload 64 \"Uploading\"\natollctl settings"
            last: true
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: page.islandUp = App.islandRunning()
    }

    Timer {
        id: confirmTimeout
        interval: 4000
        onTriggered: page.confirmingReset = false
    }
}
