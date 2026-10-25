// SPDX-FileCopyrightText: 2026 The Atoll contributors
// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import Atoll

/** A switch wired straight to a dotted config key. */
SettingRow {
    id: setting

    property string key: ""
    property bool defaultValue: false
    /**
     * Older keys for the same switch. The island needs all of them on, so the
     * switch shows on only when they all are, and flipping it sets every one.
     */
    property var alsoKeys: []

    ToggleSwitch {
        checked: Cfg.get(setting.key, setting.defaultValue)
                 && setting.alsoKeys.every(other => Cfg.get(other, setting.defaultValue))
        onToggled: value => {
            Cfg.set(setting.key, value)
            for (const other of setting.alsoKeys) {
                Cfg.set(other, value)
            }
        }
    }
}
