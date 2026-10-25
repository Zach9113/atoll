/*
 * SPDX-FileCopyrightText: 2026 The Atoll contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#pragma once

#include <QElapsedTimer>
#include <QHash>
#include <QObject>
#include <QStringList>

struct DBusMessageInfo;
class Config;

/**
 * Mirrors file transfers and other KIO jobs onto the island.
 *
 * KDE Connect transfers, Dolphin copies and the like never send a
 * notification: they report progress to Plasma's job tracker
 * (`org.kde.JobViewServerV2` and the `org.kde.JobViewV3` objects it hands
 * out). Listening in on those calls lets the island show the same progress
 * Plasma's job popup does.
 */
class JobMonitor : public QObject
{
    Q_OBJECT

public:
    explicit JobMonitor(Config *config, QObject *parent = nullptr);

    /** Feed a message from the bus tap. Returns true if it was ours. */
    bool handleMessage(const DBusMessageInfo &message);

    /** Match rules this monitor needs. */
    static QStringList matchRules();

Q_SIGNALS:
    void progress(const QString &icon, int percent, const QString &text);
    void failed(const QString &icon, const QString &text);

private:
    struct PendingView {
        QString desktopEntry;
        bool immediate = false;
    };

    struct Job {
        QString icon;
        QString title;
        bool immediate = false;
        int percent = -1;
        QElapsedTimer age;
    };

    /** Plasma also keeps quick, non-immediate jobs off screen. */
    bool worthShowing(const Job &job) const;
    static QString iconFor(const QString &desktopEntry);

    Config *m_config = nullptr;
    QHash<quint32, PendingView> m_pending; //!< requestView serial -> request
    QHash<QString, Job> m_jobs; //!< JobView object path -> job
};
