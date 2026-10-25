/*
 * SPDX-FileCopyrightText: 2026 The Atoll contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#include "appactivator.h"

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QProcess>
#include <QProcessEnvironment>
#include <QStandardPaths>
#include <QTemporaryFile>
#include <QTimer>

#ifdef ATOLL_XDG_ACTIVATION
#include <QtGui/qguiapplication_platform.h>
#include <wayland-client.h>
#include "xdg-activation-v1-client-protocol.h"
#endif

using namespace Qt::StringLiterals;

namespace
{
QString lowerKey(const QString &text)
{
    return text.trimmed().toLower();
}

// Desktop files live in the usual places, plus the exports Flatpak adds for
// its own applications, which the standard locations do not cover.
QStringList applicationDirs()
{
    static QStringList dirs;
    if (dirs.isEmpty()) {
        dirs = QStandardPaths::standardLocations(QStandardPaths::ApplicationsLocation);
        const QString dataHome = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation);
        dirs << dataHome + u"/flatpak/exports/share/applications"_s;
        dirs << u"/var/lib/flatpak/exports/share/applications"_s;
        dirs.removeDuplicates();
    }
    return dirs;
}
}

AppActivator::AppActivator(QObject *parent)
    : QObject(parent)
{
    QDBusConnection::sessionBus().registerObject(u"/Activator"_s, u"org.atoll.Activator"_s, this, QDBusConnection::ExportAllInvokables);
}

void AppActivator::markActivated(const QString &request)
{
    // KWin found and raised a window for this request: nothing needs launching.
    m_pendingRaises.remove(request);
}

void AppActivator::activate(const QString &desktopEntry, const QString &appName)
{
    // Raise a running window through KWin first. Single-instance Electron apps
    // (Vesktop, Discord, Slack) can't raise themselves on Wayland, and a raise
    // never opens a second window of anything.
    QStringList targets;
    if (!desktopEntry.isEmpty()) {
        QString entry = desktopEntry;
        if (entry.endsWith(u".desktop"_s)) {
            entry.chop(8);
        }
        targets << entry;
    }
    if (!appName.isEmpty()) {
        targets << appName;
    }
    const auto app = resolve(desktopEntry, appName);
    if (app.has_value() && !app->wmClass.isEmpty()) {
        targets << app->wmClass;
    }
    if (desktopEntry.contains(u"vesktop"_s, Qt::CaseInsensitive) || appName.contains(u"vesktop"_s, Qt::CaseInsensitive)) {
        targets << u"vesktop"_s << u"discord"_s;
    }
    targets.removeDuplicates();

    if (targets.isEmpty() || !raiseViaKWin(targets, desktopEntry, appName)) {
        launchOrActivate(desktopEntry, appName);
    }
}

bool AppActivator::raiseViaKWin(const QStringList &targets, const QString &desktopEntry, const QString &appName)
{
    auto *script = new QTemporaryFile(QDir::tempPath() + u"/atoll-kwin-activate-XXXXXX.js"_s, this);
    if (!script->open()) {
        delete script;
        return false;
    }
    const QString request = QString::number(++m_requestCounter);

    QJsonArray lowered;
    for (const QString &target : targets) {
        if (!target.trimmed().isEmpty()) {
            lowered.append(target.trimmed().toLower());
        }
    }
    // The names come from whoever sent the notification, so they go in as
    // JSON data, never as script text. Window identity is matched first; the
    // caption only as a last resort, since titles mention other apps' names.
    const QString js = uR"(
const targets = %1;
const fields = c => [c.desktopFileName, c.resourceClass, c.resourceName].map(f => (f || "").toLowerCase());
let found = null;
for (const target of targets) {
    found = workspace.windowList().find(c => fields(c).some(f => f.includes(target)));
    if (found) break;
}
if (!found) {
    for (const target of targets) {
        found = workspace.windowList().find(c => (c.caption || "").toLowerCase().includes(target));
        if (found) break;
    }
}
if (found) {
    found.minimized = false;
    workspace.activeWindow = found;
    callDBus("org.atoll.Atoll", "/Activator", "org.atoll.Activator", "markActivated", "%2");
}
)"_s.arg(QString::fromUtf8(QJsonDocument(lowered).toJson(QJsonDocument::Compact)), request);
    script->write(js.toUtf8());
    script->flush();
    const QString path = script->fileName();

    m_pendingRaises.insert(request, {desktopEntry, appName});
    // KWin answers in a few milliseconds; past this, launch the app as before.
    // The script is unloaded only here: KWin reads the file in the background
    // after run(), so unloading straight away removed it before it ever ran.
    QTimer::singleShot(RaiseWaitMs, this, [this, request, script, path = script->fileName()] {
        auto unload = QDBusMessage::createMethodCall(u"org.kde.KWin"_s, u"/Scripting"_s, u"org.kde.kwin.Scripting"_s,
                                                     u"unloadScript"_s);
        unload << path;
        QDBusConnection::sessionBus().asyncCall(unload);
        script->deleteLater();
        if (m_pendingRaises.contains(request)) {
            const auto [desktopEntry, appName] = m_pendingRaises.take(request);
            launchOrActivate(desktopEntry, appName);
        }
    });

    QDBusConnection bus = QDBusConnection::sessionBus();
    auto load = QDBusMessage::createMethodCall(u"org.kde.KWin"_s, u"/Scripting"_s, u"org.kde.kwin.Scripting"_s, u"loadScript"_s);
    load << path;
    auto *watcher = new QDBusPendingCallWatcher(bus.asyncCall(load, RaiseWaitMs), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [](QDBusPendingCallWatcher *call) {
        call->deleteLater();
        const QDBusPendingReply<int> reply = *call;
        if (!reply.isValid() || reply.value() < 0) {
            return; // no KWin scripting: the timer launches the app
        }
        QDBusConnection::sessionBus().asyncCall(QDBusMessage::createMethodCall(
            u"org.kde.KWin"_s, u"/Scripting/Script%1"_s.arg(reply.value()), u"org.kde.kwin.Script"_s, u"run"_s));
    });
    return true;
}

void AppActivator::launchOrActivate(const QString &desktopEntry, const QString &appName)
{
    const auto app = resolve(desktopEntry, appName);
    if (app.has_value()) {
        bringUp(*app);
        return;
    }

    // Nothing on disk matches. As a last resort try the name as a command -
    // some senders advertise exactly what they are - and let kstart or
    // gtk-launch have a go with whatever hint survived.
    if (!appName.isEmpty() && !QStandardPaths::findExecutable(appName).isEmpty()) {
        QProcess::startDetached(appName, {});
        return;
    }
    const QString entry = desktopEntry.isEmpty() ? appName : desktopEntry;
    if (entry.isEmpty()) {
        return;
    }
    const QString kstart = QStandardPaths::findExecutable(u"kstart"_s);
    if (!kstart.isEmpty()) {
        QProcess::startDetached(kstart, {entry.endsWith(u".desktop"_s) ? entry : entry + u".desktop"_s});
        return;
    }
    const QString gtkLaunch = QStandardPaths::findExecutable(u"gtk-launch"_s);
    if (!gtkLaunch.isEmpty()) {
        QProcess::startDetached(gtkLaunch, {entry});
    }
}

QStringList AppActivator::searchPaths() const
{
    return applicationDirs();
}

AppActivator::DesktopApp AppActivator::parseDesktopFile(const QString &path)
{
    DesktopApp app;
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return app;
    }
    app.path = path;
    app.id = QFileInfo(path).completeBaseName();
    app.matchKeys << lowerKey(app.id);

    bool inMainSection = false;
    while (!file.atEnd()) {
        const QString line = QString::fromUtf8(file.readLine()).trimmed();
        if (line.startsWith(u'[')) {
            // Only [Desktop Entry] counts; actions live in their own groups.
            inMainSection = line.compare(u"[desktop entry]"_s, Qt::CaseInsensitive) == 0;
            continue;
        }
        if (!inMainSection) {
            continue;
        }
        const int eq = line.indexOf(u'=');
        if (eq <= 0) {
            continue;
        }
        const QString key = line.left(eq).trimmed();
        // Localised names ("Name[de]") count too; anything after '[' is noise.
        const QString baseKey = key.section(u'[', 0, 0);
        const QString value = line.mid(eq + 1).trimmed();

        if (baseKey == u"Exec"_s) {
            app.exec = value;
            // The first token of the Exec line is usually the binary name.
            const QString execHead = QFileInfo(QProcess::splitCommand(value).value(0)).fileName();
            if (!execHead.isEmpty()) {
                app.matchKeys << lowerKey(execHead);
            }
        } else if (baseKey == u"StartupWMClass"_s) {
            app.wmClass = value;
            app.matchKeys << lowerKey(value);
        } else if (baseKey == u"DBusActivatable"_s) {
            app.dbusActivatable = value.compare(u"true"_s, Qt::CaseInsensitive) == 0;
        } else if (baseKey == u"Name"_s || baseKey == u"GenericName"_s || baseKey == u"Icon"_s) {
            app.matchKeys << lowerKey(value.section(u';', 0, 0));
        }
    }
    return app;
}

const QHash<QString, QString> &AppActivator::nameIndex() const
{
    if (m_indexBuilt) {
        return m_index;
    }
    m_indexBuilt = true;

    for (const QString &dir : searchPaths()) {
        QDirIterator it(dir, {u"*.desktop"_s}, QDir::Files, QDirIterator::Subdirectories);
        while (it.hasNext()) {
            const QString path = it.next();
            const DesktopApp app = parseDesktopFile(path);
            for (const QString &key : std::as_const(app.matchKeys)) {
                if (!key.isEmpty()) {
                    m_index.insert(key, path); // first writer wins
                }
            }
        }
    }
    return m_index;
}

std::optional<AppActivator::DesktopApp> AppActivator::resolve(const QString &desktopEntry, const QString &appName) const
{
    // An explicit desktop-entry hint is authoritative: go straight to it.
    QString entry = desktopEntry.trimmed();
    if (entry.endsWith(u".desktop"_s)) {
        entry.chop(8);
    }
    if (!entry.isEmpty()) {
        for (const QString &dir : searchPaths()) {
            const QString direct = dir + u'/' + entry + u".desktop"_s;
            if (QFileInfo::exists(direct)) {
                DesktopApp app = parseDesktopFile(direct);
                if (!app.exec.isEmpty() || app.dbusActivatable) {
                    return app;
                }
            }
        }
    }

    const QString key = lowerKey(appName);
    if (!key.isEmpty()) {
        const auto it = nameIndex().constFind(key);
        if (it != nameIndex().cend()) {
            DesktopApp app = parseDesktopFile(it.value());
            if (!app.exec.isEmpty() || app.dbusActivatable) {
                return app;
            }
        }
    }
    return std::nullopt;
}

QString AppActivator::expandFieldCodes(QString exec)
{
    // No file arguments travel with this launch, so every field code comes
    // out; a doubled percent survives as the literal character.
    static const QList<QChar> codes = {u'f', u'F', u'u', u'U', u'd', u'D', u'n', u'N', u'i', u'c', u'k', u'v', u'm'};
    for (int i = 0; i < exec.size() - 1;) {
        if (exec.at(i) == u'%') {
            const QChar code = exec.at(i + 1);
            if (code == u'%') {
                exec.remove(i, 1);
                ++i;
                continue;
            }
            if (codes.contains(code)) {
                exec.remove(i, 2);
                continue;
            }
        }
        ++i;
    }
    return exec.trimmed();
}

void AppActivator::bringUp(const DesktopApp &app)
{
    requestToken([this, app](const QString &token) {
        QDBusConnection bus = QDBusConnection::sessionBus();

        // Spec-shaped apps answer on their desktop id and raise themselves -
        // or start, when dbus activation is asked for and nothing is running.
        const QString busName = app.id.contains(u'.') ? app.id : QString();
        const bool reachable = !busName.isEmpty()
                && (app.dbusActivatable || bus.interface()->isServiceRegistered(busName));
        if (reachable) {
            QVariantMap platformData;
            if (!token.isEmpty()) {
                platformData.insert(u"activation-token"_s, token);
            }
            auto message =
                    QDBusMessage::createMethodCall(busName, u"/"_s, u"org.freedesktop.Application"_s, u"Activate"_s);
            message << platformData;
            bus.asyncCall(message);
            return;
        }

        // Everything else: starting it again is what makes chat clients show
        // their window - their single-instance handler raises the running
        // copy - and a fresh launch gets the token through the environment so
        // compliant toolkits take focus immediately.
        const QStringList args = QProcess::splitCommand(expandFieldCodes(app.exec));
        if (args.isEmpty()) {
            return;
        }
        if (!token.isEmpty()) {
            QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
            environment.insert(u"XDG_ACTIVATION_TOKEN"_s, token);
            environment.insert(u"DESKTOP_STARTUP_ID"_s, token);

            auto *process = new QProcess(this);
            process->setProcessEnvironment(environment);
            process->setProgram(args.first());
            process->setArguments(args.mid(1));
            process->setWorkingDirectory(QDir::homePath());
            process->startDetached();
            process->deleteLater(); // detached children are not monitored
            return;
        }

        QProcess::startDetached(args.first(), args.mid(1));
    });
}

void AppActivator::requestToken(const std::function<void(const QString &)> &done)
{
#ifdef ATOLL_XDG_ACTIVATION
    auto *wayland = qGuiApp ? qGuiApp->nativeInterface<QNativeInterface::QWaylandApplication>() : nullptr;
    wl_display *display = wayland ? wayland->display() : nullptr;
    if (!display) {
        done({});
        return;
    }

    struct TokenRequest {
        xdg_activation_v1 *activation = nullptr;
        xdg_activation_token_v1 *token = nullptr;
        QString value;
    };

    auto *request = new TokenRequest;

    auto registryGlobal = [](void *data, wl_registry *registry, uint32_t name, const char *interface,
                             uint32_t version) {
        auto *r = static_cast<TokenRequest *>(data);
        if (!r->activation && strcmp(interface, xdg_activation_v1_interface.name) == 0) {
            r->activation = static_cast<xdg_activation_v1 *>(
                    wl_registry_bind(registry, name, &xdg_activation_v1_interface, qMin(version, 1u)));
        }
    };
    auto registryRemove = [](void *, wl_registry *, uint32_t) {};
    const wl_registry_listener registryListener = {registryGlobal, registryRemove};

    auto tokenDone = [](void *data, xdg_activation_token_v1 *, const char *token) {
        static_cast<TokenRequest *>(data)->value = QString::fromUtf8(token);
    };
    const xdg_activation_token_v1_listener tokenListener = {tokenDone};

    wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registryListener, request);
    wl_display_roundtrip(display); // binds the activation factory, if there is one

    QString result;
    if (request->activation) {
        request->token = xdg_activation_v1_get_activation_token(request->activation);
        xdg_activation_token_v1_add_listener(request->token, &tokenListener, request);
        xdg_activation_token_v1_set_app_id(request->token, "io.github.atoll.Atoll");
        xdg_activation_token_v1_commit(request->token);
        wl_display_roundtrip(display); // the done event answers within this
        result = request->value;
        xdg_activation_token_v1_destroy(request->token);
        xdg_activation_v1_destroy(request->activation);
    }
    wl_registry_destroy(registry);
    delete request;

    done(result);
#else
    done({});
#endif
}
