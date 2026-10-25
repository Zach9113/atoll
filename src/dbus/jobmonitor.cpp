/*
 * SPDX-FileCopyrightText: 2026 The Atoll contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#include "jobmonitor.h"

#include "config/config.h"
#include "dbusmonitor.h"

#include <KLocalizedString>

#include <QSettings>
#include <QStandardPaths>

using namespace Qt::StringLiterals;

namespace
{
constexpr QLatin1StringView ServerInterface{"org.kde.JobViewServerV2"};
constexpr QLatin1StringView JobInterface{"org.kde.JobViewV3"};
constexpr QLatin1StringView FallbackIcon{"folder-download"};
// Matches the delay Plasma waits before it shows a non-immediate job.
constexpr qint64 ShowAfterMs = 1000;
}

JobMonitor::JobMonitor(Config *config, QObject *parent)
    : QObject(parent)
    , m_config(config)
{
}

QStringList JobMonitor::matchRules()
{
    return {
        u"type='method_call',interface='org.kde.JobViewServerV2',member='requestView'"_s,
        u"type='method_call',interface='org.kde.JobViewV3'"_s,
        // requestView answers with the job's object path; the tap only lets
        // replies with a single "u" or "o" through.
        u"type='method_return'"_s,
    };
}

QString JobMonitor::iconFor(const QString &desktopEntry)
{
    if (desktopEntry.isEmpty()) {
        return FallbackIcon;
    }
    const QString path =
        QStandardPaths::locate(QStandardPaths::ApplicationsLocation, desktopEntry + u".desktop"_s);
    if (path.isEmpty()) {
        return FallbackIcon;
    }
    QSettings desktopFile(path, QSettings::IniFormat);
    const QString icon = desktopFile.value(u"Desktop Entry/Icon"_s).toString();
    return icon.isEmpty() ? QString(FallbackIcon) : icon;
}

bool JobMonitor::worthShowing(const Job &job) const
{
    return job.immediate || job.age.elapsed() >= ShowAfterMs;
}

bool JobMonitor::handleMessage(const DBusMessageInfo &message)
{
    if (message.kind == DBusMessageInfo::MethodReturn) {
        const auto it = m_pending.constFind(message.replySerial);
        if (it == m_pending.cend()) {
            return false;
        }
        const PendingView request = *it;
        m_pending.erase(it);
        if (message.arguments.isEmpty()) {
            return true;
        }
        Job job;
        job.icon = iconFor(request.desktopEntry);
        job.immediate = request.immediate;
        job.age.start();
        m_jobs.insert(message.arguments.first().toString(), job);
        // A job whose owner crashed never terminates; don't keep it forever.
        if (m_jobs.size() > 64) {
            m_jobs.erase(m_jobs.begin());
        }
        return true;
    }

    if (message.kind != DBusMessageInfo::MethodCall) {
        return false;
    }

    if (message.interface == ServerInterface) {
        if (message.member == u"requestView"_s && message.serial != 0 && message.arguments.size() >= 3) {
            const QVariantMap hints = message.arguments.at(2).toMap();
            m_pending.insert(message.serial,
                             PendingView{message.arguments.at(0).toString(), hints.value(u"immediate"_s).toBool()});
            // Never let unanswered calls pile up.
            if (m_pending.size() > 32) {
                m_pending.erase(m_pending.begin());
            }
        }
        return true;
    }

    if (message.interface != JobInterface) {
        return false;
    }

    const auto it = m_jobs.find(message.path);
    if (it == m_jobs.end()) {
        return true;
    }
    Job &job = *it;
    const bool enabled = m_config->value(u"notifications.showTransfers"_s, true).toBool();

    if (message.member == u"update"_s && !message.arguments.isEmpty()) {
        const QVariantMap hints = message.arguments.first().toMap();
        if (hints.contains(u"title"_s)) {
            job.title = hints.value(u"title"_s).toString();
        }
        if (hints.contains(u"percent"_s)) {
            job.percent = qBound(0, hints.value(u"percent"_s).toInt(), 100);
        }
        if (enabled && job.percent >= 0 && worthShowing(job)) {
            Q_EMIT progress(job.icon, job.percent, job.title.isEmpty() ? i18n("Transferring") : job.title);
        }
        return true;
    }

    if (message.member == u"terminate"_s) {
        const uint errorCode = message.arguments.isEmpty() ? 0 : message.arguments.first().toUInt();
        const QString errorText = message.arguments.size() > 1 ? message.arguments.at(1).toString() : QString();
        if (enabled && worthShowing(job)) {
            // Error code 1 is KJob::KilledJobError, a cancel by the user.
            if (errorCode == 0) {
                Q_EMIT progress(job.icon, 100, job.title.isEmpty() ? i18n("Transfer finished") : job.title);
            } else if (errorCode != 1) {
                Q_EMIT failed(u"dialog-error"_s, errorText.isEmpty() ? i18n("Transfer failed") : errorText);
            }
        }
        m_jobs.erase(it);
        return true;
    }

    return true;
}
