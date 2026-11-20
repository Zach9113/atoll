/*
 * SPDX-FileCopyrightText: 2026 The Atoll contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#include "kdeconnectreply.h"

#include <KLocalizedString>

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusReply>
#include <QVariantMap>

using namespace Qt::StringLiterals;

namespace
{
constexpr QLatin1StringView Service{"org.kde.kdeconnect"};
constexpr QLatin1StringView NotificationInterface{"org.kde.kdeconnect.device.notifications.notification"};
// A click waits on these, so a KDE Connect that hangs must not hang the island with it.
constexpr int TimeoutMs = 1500;

QDBusMessage call(const QString &path, const QString &interface, const QString &method, const QVariantList &arguments = {})
{
    auto message = QDBusMessage::createMethodCall(QString(Service), path, interface, method);
    message.setArguments(arguments);
    return QDBusConnection::sessionBus().call(message, QDBus::Block, TimeoutMs);
}

QStringList stringList(const QDBusMessage &reply)
{
    return reply.type() == QDBusMessage::ReplyMessage && !reply.arguments().isEmpty()
        ? reply.arguments().constFirst().toStringList()
        : QStringList();
}

/**
 * KDE Connect escapes the text it shows on the desktop, and whitespace and an ellipsis at the end differ
 * between the phone's text and the desktop's; nothing else may.
 */
QString comparable(QString text)
{
    text.replace(u"&lt;"_s, u"<"_s).replace(u"&gt;"_s, u">"_s).replace(u"&quot;"_s, u"\""_s)
        .replace(u"&#39;"_s, u"'"_s).replace(u"&amp;"_s, u"&"_s);
    text = text.simplified();
    while (text.endsWith(u'…') || text.endsWith(u'.')) {
        text.chop(1);
    }
    return text.trimmed();
}

bool appearsIn(const QString &part, const QString &whole)
{
    return !part.isEmpty() && whole.contains(part, Qt::CaseInsensitive);
}
} // namespace

bool replyThroughKdeConnect(const QString &summary, const QString &body, const QString &text, QString *error)
{
    const QString shownSummary = comparable(summary);
    const QString shownBody = comparable(body);
    const QString shown = shownSummary + u'\n' + shownBody;

    const QStringList devices =
        stringList(call(u"/modules/kdeconnect"_s, u"org.kde.kdeconnect.daemon"_s, u"devices"_s, {true, true}));
    if (devices.isEmpty()) {
        *error = i18n("Your phone isn't connected through KDE Connect.");
        return false;
    }

    QString chosenPath;
    int chosenNumber = -1;
    for (const QString &device : devices) {
        const QString base = u"/modules/kdeconnect/devices/%1/notifications"_s.arg(device);
        const QStringList ids =
            stringList(call(base, u"org.kde.kdeconnect.device.notifications"_s, u"activeNotifications"_s));
        for (const QString &id : ids) {
            const QString path = base + u'/' + id;
            const QDBusMessage reply = call(path, u"org.freedesktop.DBus.Properties"_s, u"GetAll"_s,
                                            {QString(NotificationInterface)});
            if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty()) {
                continue;
            }
            const QVariantMap properties = qdbus_cast<QVariantMap>(reply.arguments().constFirst());
            if (properties.value(u"replyId"_s).toString().isEmpty()) {
                continue; // an app that takes no reply, like a shop's offer
            }
            const QString title = comparable(properties.value(u"title"_s).toString());
            const QString phoneText = comparable(properties.value(u"text"_s).toString());
            // the desktop may shorten the text, so either may hold the other
            const bool sameText = phoneText.isEmpty() || appearsIn(phoneText.left(40), shownBody)
                || appearsIn(shownBody.left(40), phoneText);
            if (!appearsIn(title, shown) || !sameText) {
                continue;
            }
            const int number = id.toInt();
            if (number > chosenNumber) {
                chosenNumber = number;
                chosenPath = path;
            }
        }
    }

    if (chosenPath.isEmpty()) {
        *error = i18n("KDE Connect can't reply to this notification from the PC.");
        return false;
    }
    const QDBusMessage sent = call(chosenPath, QString(NotificationInterface), u"sendReply"_s, {text});
    if (sent.type() == QDBusMessage::ErrorMessage) {
        *error = i18n("KDE Connect didn't send the reply: %1", sent.errorMessage());
        return false;
    }
    return true;
}
