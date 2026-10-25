/*
 * SPDX-FileCopyrightText: 2026 The Atoll contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#pragma once

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusServiceWatcher>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

class CrankedService : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Accessed through App.cranked")

    Q_PROPERTY(bool available READ available NOTIFY changed)
    Q_PROPERTY(bool mixerConnected READ mixerConnected NOTIFY changed)
    Q_PROPERTY(QString profile READ profile NOTIFY changed)
    Q_PROPERTY(QVariantList knobs READ knobs NOTIFY changed)
    Q_PROPERTY(int count READ count NOTIFY changed)

public:
    explicit CrankedService(QObject *parent = nullptr);

    bool available() const
    {
        return m_available;
    }
    bool mixerConnected() const
    {
        return m_mixerConnected;
    }
    QString profile() const
    {
        return m_profile;
    }
    QVariantList knobs() const
    {
        return m_knobs;
    }
    int count() const
    {
        return m_knobs.size();
    }

    Q_INVOKABLE void setKnob(int index, int percent);
    Q_INVOKABLE void stepKnob(int index, int delta);
    Q_INVOKABLE void press(int index);
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void openWindow();

Q_SIGNALS:
    void changed();

private Q_SLOTS:
    void onStateChanged(const QString &stateJson);
    void updateAvailability();

private:
    void parseState(const QString &stateJson);

    bool m_available = false;
    bool m_mixerConnected = false;
    QString m_profile;
    QVariantList m_knobs;
    QDBusServiceWatcher *m_watcher = nullptr;
};
