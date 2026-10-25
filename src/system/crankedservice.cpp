/*
 * SPDX-FileCopyrightText: 2026 The Atoll contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#include "crankedservice.h"

#include <QDBusConnectionInterface>
#include <QDBusReply>
#include <QDir>
#include <QFile>
#include <QProcess>
#include <QStandardPaths>

namespace
{
const QString ServiceName = QStringLiteral("io.github.zach9113.CrankedAudio");
const QString ObjectPath = QStringLiteral("/io/github/zach9113/CrankedAudio");
const QString InterfaceName = QStringLiteral("io.github.zach9113.CrankedAudio1");
}

CrankedService::CrankedService(QObject *parent)
    : QObject(parent)
{
    m_watcher = new QDBusServiceWatcher(ServiceName,
                                        QDBusConnection::sessionBus(),
                                        QDBusServiceWatcher::WatchForRegistration | QDBusServiceWatcher::WatchForUnregistration,
                                        this);

    connect(m_watcher, &QDBusServiceWatcher::serviceRegistered, this, [this]() {
        updateAvailability();
        refresh();
    });

    connect(m_watcher, &QDBusServiceWatcher::serviceUnregistered, this, [this]() {
        m_available = false;
        m_knobs.clear();
        Q_EMIT changed();
    });

    QDBusConnection::sessionBus().connect(
        ServiceName,
        ObjectPath,
        InterfaceName,
        QStringLiteral("StateChanged"),
        this,
        SLOT(onStateChanged(QString)));

    updateAvailability();
    if (m_available) {
        refresh();
    }
}

void CrankedService::updateAvailability()
{
    const bool wasAvailable = m_available;
    m_available = QDBusConnection::sessionBus().interface()->isServiceRegistered(ServiceName);
    if (wasAvailable != m_available) {
        Q_EMIT changed();
    }
}

void CrankedService::onStateChanged(const QString &stateJson)
{
    parseState(stateJson);
}

void CrankedService::parseState(const QString &stateJson)
{
    const QJsonDocument doc = QJsonDocument::fromJson(stateJson.toUtf8());
    if (!doc.isObject()) {
        return;
    }

    const QJsonObject root = doc.object();
    m_mixerConnected = root.value(QStringLiteral("mixer")).toBool(false);
    m_profile = root.value(QStringLiteral("profile")).toString();

    const QJsonArray knobArray = root.value(QStringLiteral("knobs")).toArray();
    QVariantList list;
    list.reserve(knobArray.size());

    for (int i = 0; i < knobArray.size(); ++i) {
        const QJsonObject k = knobArray.at(i).toObject();
        QVariantMap map;
        map.insert(QStringLiteral("index"), i);
        map.insert(QStringLiteral("name"), k.value(QStringLiteral("name")).toString());

        const QJsonValue lvlVal = k.value(QStringLiteral("level"));
        map.insert(QStringLiteral("level"), lvlVal.isNull() ? -1 : lvlVal.toInt(-1));

        map.insert(QStringLiteral("color"), k.value(QStringLiteral("color")).toString(QStringLiteral("#ffffff")));
        map.insert(QStringLiteral("background"), k.value(QStringLiteral("background")).toString(QStringLiteral("#000000")));
        map.insert(QStringLiteral("mutedColor"), k.value(QStringLiteral("muted_color")).toString(QStringLiteral("#000000")));
        map.insert(QStringLiteral("muted"), k.value(QStringLiteral("muted")).toBool(false));
        map.insert(QStringLiteral("lowered"), k.value(QStringLiteral("lowered")).toBool(false));
        map.insert(QStringLiteral("source"), k.value(QStringLiteral("source")).toString());
        map.insert(QStringLiteral("press"), k.value(QStringLiteral("press")).toString());
        map.insert(QStringLiteral("hold"), k.value(QStringLiteral("hold")).toString());
        list.append(map);
    }

    m_knobs = list;
    m_available = true;
    Q_EMIT changed();
}

void CrankedService::refresh()
{
    QDBusMessage msg = QDBusMessage::createMethodCall(ServiceName, ObjectPath, InterfaceName, QStringLiteral("GetState"));
    const QDBusReply<QString> reply = QDBusConnection::sessionBus().call(msg);
    if (reply.isValid()) {
        parseState(reply.value());
    }
}

void CrankedService::setKnob(int index, int percent)
{
    if (index < 0) {
        return;
    }
    // Optimistic local update so UI moves immediately
    if (index < m_knobs.size()) {
        QVariantMap map = m_knobs.at(index).toMap();
        map.insert(QStringLiteral("level"), qBound(0, percent, 100));
        m_knobs.replace(index, map);
        Q_EMIT changed();
    }

    QDBusMessage msg = QDBusMessage::createMethodCall(ServiceName, ObjectPath, InterfaceName, QStringLiteral("SetKnob"));
    msg << static_cast<quint32>(index) << static_cast<quint32>(qBound(0, percent, 100));
    QDBusConnection::sessionBus().send(msg);
}

void CrankedService::stepKnob(int index, int delta)
{
    if (index < 0) {
        return;
    }
    QDBusMessage msg = QDBusMessage::createMethodCall(ServiceName, ObjectPath, InterfaceName, QStringLiteral("StepKnob"));
    msg << static_cast<quint32>(index) << static_cast<qint32>(delta);
    QDBusConnection::sessionBus().send(msg);
}

void CrankedService::press(int index)
{
    if (index < 0) {
        return;
    }
    QDBusMessage msg = QDBusMessage::createMethodCall(ServiceName, ObjectPath, InterfaceName, QStringLiteral("Press"));
    msg << static_cast<quint32>(index);
    QDBusConnection::sessionBus().send(msg);
}

void CrankedService::openWindow()
{
    QDBusMessage msg = QDBusMessage::createMethodCall(ServiceName, ObjectPath, InterfaceName, QStringLiteral("OpenWindow"));
    QDBusMessage reply = QDBusConnection::sessionBus().call(msg);
    if (reply.type() == QDBusMessage::ReplyMessage) {
        return;
    }

    const QString localBin = QDir::homePath() + QStringLiteral("/.local/bin/cranked-audio");
    if (QFile::exists(localBin)) {
        QProcess::startDetached(localBin, {});
        return;
    }
    const QString cranked = QStandardPaths::findExecutable(QStringLiteral("cranked-audio"));
    if (!cranked.isEmpty()) {
        QProcess::startDetached(cranked, {});
    }
}
