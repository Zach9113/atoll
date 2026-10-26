/*
 * SPDX-FileCopyrightText: 2026 The Atoll contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#pragma once

#include <QObject>
#include <QProcess>
#include <QtQml/qqmlregistration.h>

#include "dbus/notificationmonitor.h"

class Config;
class QLockFile;
class QNetworkAccessManager;
class QTimer;

/**
 * Checks the fork's GitHub releases and installs a newer one.
 *
 * A release is a tag, not a prebuilt package: Atoll links Qt's private API,
 * so a package built against another Qt than the one installed here would not
 * even start. Installing therefore builds the tagged source with makepkg as
 * the user, then hands the package to pacman through pkexec, which asks for
 * the password in Plasma's own dialog, and restarts the island.
 *
 * Only an `atoll-git` package that pacman owns is updated this way; any other
 * install is only told that a release is out and where to find it.
 */
class Updater : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Owned by App")

    /** idle, checking, upToDate, available, building, installing, failed */
    Q_PROPERTY(QString state READ state NOTIFY stateChanged)
    /** What the settings page says under the version, for any state. */
    Q_PROPERTY(QString message READ message NOTIFY stateChanged)
    Q_PROPERTY(QString latestVersion READ latestVersion NOTIFY stateChanged)
    Q_PROPERTY(QString releaseUrl READ releaseUrl NOTIFY stateChanged)
    /** Whether this install can update itself, rather than only being told. */
    Q_PROPERTY(bool canInstall READ canInstall CONSTANT)
    Q_PROPERTY(bool busy READ busy NOTIFY stateChanged)

public:
    /** The openUrl of the island's "update available" entry. */
    static constexpr QLatin1StringView OpenUrl{"atoll-update:"};

    explicit Updater(Config *config, QObject *parent = nullptr);
    ~Updater() override;

    /** Schedule the automatic checks; the island calls this, the settings window does not. */
    void startChecking();

    QString state() const
    {
        return m_state;
    }
    QString message() const
    {
        return m_message;
    }
    QString latestVersion() const
    {
        return m_latestVersion;
    }
    QString releaseUrl() const
    {
        return m_releaseUrl;
    }
    bool canInstall() const
    {
        return m_canInstall;
    }
    bool busy() const;

    Q_INVOKABLE void check();
    /** Build and install the latest release, or open its page when this install cannot update itself. */
    Q_INVOKABLE void install();
    /** For the island's entry: install() when the url is ours. */
    void open(const QString &openUrl);

    /** "0.2.0" is newer than "v0.1.9"; anything unreadable is never newer. */
    static bool isNewer(const QString &latest, const QString &current);

Q_SIGNALS:
    void stateChanged();
    /** A newer release than the one running was found, once per version. */
    void available(const NotificationData &entry);
    /** A step worth putting on the island while the settings window is shut. */
    void progress(const QString &icon, const QString &text);

private:
    void setState(const QString &state, const QString &message);
    void fail(const QString &message);
    void onReleaseReply(const QByteArray &body);
    void build();
    void installPackage(const QString &package);
    void restartIsland();
    QString workDir() const;
    QString pkgbuild() const;

    Config *m_config;
    QNetworkAccessManager *m_network = nullptr;
    QTimer *m_timer = nullptr;
    QProcess *m_process = nullptr;
    QLockFile *m_lock = nullptr;
    QString m_state = QStringLiteral("idle");
    QString m_message;
    QString m_latestVersion;
    QString m_releaseUrl;
    QString m_announcedVersion;
    bool m_canInstall = false;
    bool m_installAfterCheck = false;
};
