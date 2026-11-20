/*
 * SPDX-FileCopyrightText: 2026 The Atoll contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#pragma once

#include <QString>

/**
 * Replies to a phone notification that KDE Connect mirrored, through KDE Connect itself.
 *
 * A reply cannot go back the way the notification came: KDE Connect only listens for a reply from the
 * notification daemon, and Atoll merely watches the bus. KDE Connect does keep every mirrored notification
 * as an object of its own, though, and the ones a messaging app lets you answer (they carry a reply id)
 * take a reply directly. The one meant is the newest whose title and text appear in the desktop
 * notification.
 *
 * Returns false, with `error` saying why, when no such notification is there to reply to.
 */
bool replyThroughKdeConnect(const QString &summary, const QString &body, const QString &text, QString *error);
