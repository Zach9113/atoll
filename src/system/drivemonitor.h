/*
 * SPDX-FileCopyrightText: 2026 The Atoll contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#pragma once

#include <QDBusObjectPath>
#include <QHash>
#include <QObject>
#include <QVariantMap>

#include "dbus/notificationmonitor.h"

class Config;

/**
 * Announces drives as they are plugged in.
 *
 * Plasma's Device Notifier opens its own popup for a new drive and sends no
 * notification, so there is nothing on the session bus to mirror. This
 * watches UDisks2 on the system bus instead and posts an entry of its own;
 * clicking it mounts the drive if needed and opens it in the file manager.
 */
class DriveMonitor : public QObject
{
    Q_OBJECT

public:
    /** The openUrl prefix of a drive entry; the rest is the UDisks2 block object path. */
    static constexpr QLatin1StringView OpenUrlPrefix{"atoll-drive:"};

    explicit DriveMonitor(Config *config, QObject *parent = nullptr);

    /** Mount the filesystem behind an entry's openUrl if needed and open it. */
    void open(const QString &openUrl);

Q_SIGNALS:
    /** A drive was plugged in, for the island and its list. */
    void connected(const NotificationData &entry);
    /** The drive behind this entry is gone, so its entry should go too. */
    void disconnected(quint64 uid);
    void failed(const QString &icon, const QString &text);

private Q_SLOTS:
    void onInterfacesAdded(const QDBusObjectPath &path, const QVariantMap &interfaces);
    void onInterfacesRemoved(const QDBusObjectPath &path, const QStringList &interfaces);

private:
    void announce(const QString &blockPath, const QVariantMap &block);
    void openMounted(const QString &blockPath, const QString &name);

    Config *m_config;
    quint64 m_nextUid = quint64(1) << 49;
    QHash<QString, quint64> m_entries; //!< block object path -> list entry uid
    QHash<QString, QString> m_names; //!< block object path -> name shown in the entry
};
