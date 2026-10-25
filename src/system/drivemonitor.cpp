/*
 * SPDX-FileCopyrightText: 2026 The Atoll contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#include "drivemonitor.h"

#include "config/config.h"

#include <KLocalizedString>

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusVariant>
#include <QDateTime>
#include <QDesktopServices>
#include <QLocale>
#include <QUrl>

using namespace Qt::StringLiterals;

namespace
{
constexpr QLatin1StringView UDisksService{"org.freedesktop.UDisks2"};
constexpr QLatin1StringView UDisksRoot{"/org/freedesktop/UDisks2"};
constexpr QLatin1StringView ObjectManager{"org.freedesktop.DBus.ObjectManager"};
constexpr QLatin1StringView Properties{"org.freedesktop.DBus.Properties"};
constexpr QLatin1StringView BlockInterface{"org.freedesktop.UDisks2.Block"};
constexpr QLatin1StringView DriveInterface{"org.freedesktop.UDisks2.Drive"};
constexpr QLatin1StringView FilesystemInterface{"org.freedesktop.UDisks2.Filesystem"};
// Mounting can wait on a polkit prompt.
constexpr int MountTimeoutMs = 60'000;

QDBusPendingCallWatcher *getAll(const QString &path, QLatin1StringView interface, QObject *parent)
{
    auto message = QDBusMessage::createMethodCall(QString(UDisksService), path, QString(Properties), u"GetAll"_s);
    message << QString(interface);
    return new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(message), parent);
}
} // namespace

DriveMonitor::DriveMonitor(Config *config, QObject *parent)
    : QObject(parent)
    , m_config(config)
{
    auto bus = QDBusConnection::systemBus();
    bus.connect(QString(UDisksService),
                QString(UDisksRoot),
                QString(ObjectManager),
                u"InterfacesAdded"_s,
                this,
                SLOT(onInterfacesAdded(QDBusObjectPath, QVariantMap)));
    bus.connect(QString(UDisksService),
                QString(UDisksRoot),
                QString(ObjectManager),
                u"InterfacesRemoved"_s,
                this,
                SLOT(onInterfacesRemoved(QDBusObjectPath, QStringList)));
}

void DriveMonitor::onInterfacesAdded(const QDBusObjectPath &path, const QVariantMap &interfaces)
{
    // A filesystem is what can be opened; a bare disk or partition table is not.
    if (!interfaces.contains(FilesystemInterface) || !m_config->value(u"notifications.showDrives"_s, true).toBool()) {
        return;
    }
    const QString blockPath = path.path();
    auto *watcher = getAll(blockPath, BlockInterface, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, blockPath](QDBusPendingCallWatcher *self) {
        self->deleteLater();
        const QDBusPendingReply<QVariantMap> reply = *self;
        if (!reply.isError()) {
            announce(blockPath, reply.value());
        }
    });
}

void DriveMonitor::onInterfacesRemoved(const QDBusObjectPath &path, const QStringList &interfaces)
{
    if (!interfaces.contains(FilesystemInterface)) {
        return;
    }
    m_names.remove(path.path());
    const auto it = m_entries.constFind(path.path());
    if (it != m_entries.cend()) {
        Q_EMIT disconnected(it.value());
        m_entries.erase(it);
    }
}

void DriveMonitor::announce(const QString &blockPath, const QVariantMap &block)
{
    // Internal disks carry HintSystem, and loop devices and zram have no drive.
    const QString drivePath = block.value(u"Drive"_s).value<QDBusObjectPath>().path();
    if (block.value(u"HintIgnore"_s).toBool() || block.value(u"HintSystem"_s).toBool() || drivePath.isEmpty()
        || drivePath == u"/"_s) {
        return;
    }

    auto *watcher = getAll(drivePath, DriveInterface, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, blockPath, block](QDBusPendingCallWatcher *self) {
        self->deleteLater();
        const QDBusPendingReply<QVariantMap> reply = *self;
        const QVariantMap drive = reply.isError() ? QVariantMap() : reply.value();

        const QString label = block.value(u"HintName"_s).toString().isEmpty()
            ? block.value(u"IdLabel"_s).toString()
            : block.value(u"HintName"_s).toString();
        const QString model =
            u"%1 %2"_s.arg(drive.value(u"Vendor"_s).toString(), drive.value(u"Model"_s).toString()).simplified();
        const QString name = !label.isEmpty() ? label : (!model.isEmpty() ? model : i18n("Removable drive"));
        const QString icon = block.value(u"HintIconName"_s).toString();
        const bool usb = drive.value(u"ConnectionBus"_s).toString() == u"usb"_s;

        NotificationData entry;
        entry.uid = m_nextUid++;
        entry.appName = i18n("Devices");
        entry.appIcon = !icon.isEmpty() ? icon : (usb ? u"drive-removable-media-usb"_s : u"drive-removable-media"_s);
        entry.summary = i18nc("@title drive name", "%1 connected", name);
        const quint64 size = block.value(u"Size"_s).toULongLong();
        entry.body = size > 0 ? i18nc("@info drive size", "%1 · click to open", QLocale().formattedDataSize(qint64(size)))
                              : i18n("Click to open");
        entry.openUrl = QString(OpenUrlPrefix) + blockPath;
        entry.timestamp = QDateTime::currentDateTime();

        m_entries.insert(blockPath, entry.uid);
        m_names.insert(blockPath, name);
        Q_EMIT connected(entry);
    });
}

void DriveMonitor::open(const QString &openUrl)
{
    if (!openUrl.startsWith(OpenUrlPrefix)) {
        return;
    }
    const QString blockPath = openUrl.mid(OpenUrlPrefix.size());
    const QString name = m_names.value(blockPath, i18n("the drive"));

    auto message = QDBusMessage::createMethodCall(QString(UDisksService), blockPath, QString(Properties), u"Get"_s);
    message << QString(FilesystemInterface) << u"MountPoints"_s;
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(message), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, blockPath, name](QDBusPendingCallWatcher *self) {
        self->deleteLater();
        const QDBusPendingReply<QDBusVariant> reply = *self;
        if (reply.isError()) {
            Q_EMIT failed(u"dialog-error"_s, i18n("%1 is no longer connected", name));
            return;
        }
        // MountPoints is aay: NUL-terminated paths.
        const QList<QByteArray> mountPoints = qdbus_cast<QList<QByteArray>>(reply.value().variant().value<QDBusArgument>());
        if (!mountPoints.isEmpty()) {
            QByteArray mountPoint = mountPoints.constFirst();
            if (mountPoint.endsWith('\0')) {
                mountPoint.chop(1);
            }
            QDesktopServices::openUrl(QUrl::fromLocalFile(QString::fromLocal8Bit(mountPoint)));
            return;
        }
        openMounted(blockPath, name);
    });
}

void DriveMonitor::openMounted(const QString &blockPath, const QString &name)
{
    auto message = QDBusMessage::createMethodCall(QString(UDisksService), blockPath, QString(FilesystemInterface), u"Mount"_s);
    message << QVariantMap();
    auto *watcher =
        new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(message, MountTimeoutMs), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, name](QDBusPendingCallWatcher *self) {
        self->deleteLater();
        const QDBusPendingReply<QString> reply = *self;
        if (reply.isError()) {
            Q_EMIT failed(u"dialog-error"_s, i18n("Could not open %1: %2", name, reply.error().message()));
            return;
        }
        QDesktopServices::openUrl(QUrl::fromLocalFile(reply.value()));
    });
}
