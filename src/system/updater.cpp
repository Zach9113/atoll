/*
 * SPDX-FileCopyrightText: 2026 The Atoll contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#include "updater.h"

#include "config/config.h"

#include <KLocalizedString>

#include <QCoreApplication>
#include <QDateTime>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLockFile>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcessEnvironment>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>
#include <QVersionNumber>

using namespace Qt::StringLiterals;

namespace
{
constexpr QLatin1StringView Repository{"Zach9113/atoll"};
constexpr QLatin1StringView PackageName{"atoll-git"};
constexpr QLatin1StringView BranchSource{"#branch=zach-patches"};
constexpr int FirstCheckMs = 2 * 60 * 1000;
constexpr int CheckIntervalMs = 6 * 60 * 60 * 1000;
// pkexec's exit codes when the password dialog was dismissed or refused.
constexpr int PkexecDismissed = 126;
constexpr int PkexecNotAuthorized = 127;

/** The last "==> ERROR:" or "error:" line of a log, which is what went wrong. */
QString lastError(const QString &logPath)
{
    QFile log(logPath);
    if (!log.open(QIODevice::ReadOnly)) {
        return {};
    }
    const QStringList lines = QString::fromLocal8Bit(log.readAll()).split(u'\n', Qt::SkipEmptyParts);
    for (auto it = lines.crbegin(); it != lines.crend(); ++it) {
        if (it->contains(u"ERROR:"_s) || it->startsWith(u"error:"_s)) {
            return it->trimmed();
        }
    }
    return lines.isEmpty() ? QString() : lines.constLast().trimmed();
}

/** The systemd unit this process runs in, from its cgroup, or empty outside one. */
QString ownUnit()
{
    QFile cgroup(u"/proc/self/cgroup"_s);
    if (!cgroup.open(QIODevice::ReadOnly)) {
        return {};
    }
    const QStringList parts = QString::fromLocal8Bit(cgroup.readAll()).trimmed().split(u'/');
    for (auto it = parts.crbegin(); it != parts.crend(); ++it) {
        if (it->endsWith(u".service"_s)) {
            return *it;
        }
    }
    return {};
}

bool runQuietly(const QString &program, const QStringList &arguments, QString *output = nullptr)
{
    QProcess process;
    process.start(program, arguments);
    if (!process.waitForFinished(3000)) {
        process.kill();
        return false;
    }
    if (output) {
        *output = QString::fromLocal8Bit(process.readAllStandardOutput()).trimmed();
    }
    return process.exitStatus() == QProcess::NormalExit && process.exitCode() == 0;
}
} // namespace

Updater::Updater(Config *config, QObject *parent)
    : QObject(parent)
    , m_config(config)
    , m_network(new QNetworkAccessManager(this))
{
    const bool tools = !QStandardPaths::findExecutable(u"pacman"_s).isEmpty()
        && !QStandardPaths::findExecutable(u"makepkg"_s).isEmpty()
        && !QStandardPaths::findExecutable(u"pkexec"_s).isEmpty();
    QString owner;
    m_canInstall = tools
        && runQuietly(u"pacman"_s, {u"-Qqo"_s, QCoreApplication::applicationFilePath()}, &owner)
        && owner == PackageName;
}

Updater::~Updater()
{
    delete m_lock;
}

void Updater::startChecking()
{
    m_timer = new QTimer(this);
    connect(m_timer, &QTimer::timeout, this, [this] {
        m_timer->setInterval(CheckIntervalMs);
        if (m_config->value(u"updates.check"_s, true).toBool() && !busy()) {
            check();
        }
    });
    m_timer->start(FirstCheckMs);
}

bool Updater::busy() const
{
    return m_state == u"checking"_s || m_state == u"building"_s || m_state == u"installing"_s;
}

bool Updater::isNewer(const QString &latest, const QString &current)
{
    const auto parse = [](QString text) {
        text = text.trimmed();
        if (text.startsWith(u'v')) {
            text.remove(0, 1);
        }
        qsizetype suffix = -1;
        const QVersionNumber version = QVersionNumber::fromString(text, &suffix);
        // "1.2.3-rc1" or "1.2" are not releases this compares; a version it
        // cannot read must never look newer, or it could offer an odd build.
        return (version.segmentCount() == 3 && suffix == text.size()) ? version : QVersionNumber();
    };
    const QVersionNumber l = parse(latest);
    const QVersionNumber c = parse(current);
    return !l.isNull() && !c.isNull() && l > c;
}

void Updater::setState(const QString &state, const QString &message)
{
    m_state = state;
    m_message = message;
    Q_EMIT stateChanged();
}

void Updater::fail(const QString &message)
{
    delete m_lock;
    m_lock = nullptr;
    m_installAfterCheck = false;
    setPercent(-1, {});
    setState(u"failed"_s, message);
}

void Updater::setPercent(int percent, const QString &text)
{
    if (percent == m_percent) {
        return;
    }
    m_percent = percent;
    Q_EMIT percentChanged();
    if (percent >= 0) {
        Q_EMIT progress(u"system-software-update"_s, percent, text);
    }
}

void Updater::onBuildOutput()
{
    const QByteArray output = m_process->readAllStandardOutput();
    if (m_log) {
        m_log->write(output);
    }
    m_pendingOutput += output;

    // makepkg's own steps, then ninja's "[done/total]" for the long part in between.
    static const QRegularExpression ninjaStep(u"^\\[(\\d+)/(\\d+)\\]"_s);
    const QString building = i18n("Building Atoll %1", m_latestVersion);
    qsizetype end;
    while ((end = m_pendingOutput.indexOf('\n')) >= 0) {
        const QString line = QString::fromLocal8Bit(m_pendingOutput.left(end)).trimmed();
        m_pendingOutput.remove(0, end + 1);
        if (line.startsWith(u"==> Retrieving sources"_s)) {
            setPercent(5, i18n("Downloading Atoll %1", m_latestVersion));
        } else if (line.startsWith(u"==> Starting build()"_s)) {
            setPercent(10, building);
        } else if (const auto match = ninjaStep.match(line); match.hasMatch() && match.captured(2).toInt() > 0) {
            setPercent(10 + 75 * match.captured(1).toInt() / match.captured(2).toInt(), building);
        } else if (line.startsWith(u"==> Starting package()"_s)) {
            setPercent(87, building);
        } else if (line.startsWith(u"==> Creating package"_s)) {
            setPercent(90, building);
        }
    }
}

void Updater::check()
{
    if (busy()) {
        return;
    }
    setState(u"checking"_s, i18n("Checking for updates…"));

    const QString api = qEnvironmentVariable("ATOLL_UPDATE_API",
                                             u"https://api.github.com/repos/%1/releases/latest"_s.arg(Repository));
    QNetworkRequest request{QUrl(api)};
    request.setHeader(QNetworkRequest::UserAgentHeader, u"atoll-updater"_s);
    request.setRawHeader("Accept", "application/vnd.github+json");
    request.setTransferTimeout(20'000);
    QNetworkReply *reply = m_network->get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        reply->deleteLater();
        if (reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt() == 404) {
            // No release published yet.
            m_installAfterCheck = false;
            setState(u"upToDate"_s, i18n("Atoll is up to date."));
            return;
        }
        if (reply->error() != QNetworkReply::NoError) {
            fail(i18n("Could not reach GitHub (%1).", reply->errorString()));
            return;
        }
        onReleaseReply(reply->readAll());
    });
}

void Updater::onReleaseReply(const QByteArray &body)
{
    const QJsonObject release = QJsonDocument::fromJson(body).object();
    const QString tag = release.value(u"tag_name"_s).toString();
    if (tag.isEmpty()) {
        fail(i18n("GitHub's answer had no release in it."));
        return;
    }
    m_releaseUrl = release.value(u"html_url"_s).toString();
    m_latestVersion = tag.startsWith(u'v') ? tag.mid(1) : tag;

    if (!isNewer(m_latestVersion, QCoreApplication::applicationVersion())) {
        m_installAfterCheck = false;
        setState(u"upToDate"_s, i18n("Atoll is up to date."));
        return;
    }

    setState(u"available"_s, i18n("Atoll %1 is available.", m_latestVersion));
    if (m_installAfterCheck) {
        m_installAfterCheck = false;
        install();
        return;
    }
    if (m_announcedVersion != m_latestVersion) {
        m_announcedVersion = m_latestVersion;
        NotificationData entry;
        entry.uid = (quint64(1) << 50) + QDateTime::currentSecsSinceEpoch();
        entry.appName = u"Atoll"_s;
        entry.appIcon = u"system-software-update"_s;
        entry.summary = i18n("Atoll %1 is available", m_latestVersion);
        entry.body = m_canInstall ? i18n("Click to update. It builds in the background, then asks for your password.")
                                  : i18n("Click to see what's new.");
        entry.openUrl = m_canInstall ? QString(OpenUrl) : m_releaseUrl;
        entry.timestamp = QDateTime::currentDateTime();
        Q_EMIT available(entry);
    }
}

void Updater::open(const QString &openUrl)
{
    if (openUrl.startsWith(OpenUrl)) {
        install();
    }
}

void Updater::install()
{
    if (busy()) {
        return;
    }
    if (m_state != u"available"_s) {
        // Never install from a stale answer: ask GitHub again first.
        m_installAfterCheck = true;
        check();
        return;
    }
    if (!m_canInstall) {
        QDesktopServices::openUrl(QUrl(m_releaseUrl));
        return;
    }

    // The island and the settings window each have an Updater; one build at a time.
    QDir().mkpath(QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation) + u"/atoll"_s);
    m_lock = new QLockFile(QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation)
                           + u"/atoll/update.lock"_s);
    if (!m_lock->tryLock(0)) {
        fail(i18n("An update is already running."));
        return;
    }
    build();
}

QString Updater::workDir() const
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation) + u"/atoll/update"_s;
}

QString Updater::pkgbuild() const
{
    QFile file(u":/atoll/packaging/PKGBUILD-git"_s);
    if (!file.open(QIODevice::ReadOnly)) {
        return {};
    }
    QString text = QString::fromUtf8(file.readAll());
    if (!text.contains(BranchSource)) {
        return {};
    }
    // ATOLL_UPDATE_SOURCE replaces the whole source, so the update can be
    // tried against a local checkout without publishing a release.
    const QString source = qEnvironmentVariable("ATOLL_UPDATE_SOURCE");
    if (!source.isEmpty()) {
        static const QRegularExpression sourceLine(u"^source=.*$"_s, QRegularExpression::MultilineOption);
        return text.replace(sourceLine, u"source=(\"atoll::%1\")"_s.arg(source));
    }
    return text.replace(BranchSource, u"#tag=v%1"_s.arg(m_latestVersion));
}

void Updater::build()
{
    const QString dir = workDir();
    QDir(dir).removeRecursively();
    QDir().mkpath(dir);
    const QString recipe = pkgbuild();
    QFile file(dir + u"/PKGBUILD"_s);
    if (recipe.isEmpty() || !file.open(QIODevice::WriteOnly) || file.write(recipe.toUtf8()) < 0) {
        fail(i18n("Could not prepare the build in %1.", dir));
        return;
    }
    file.close();

    const QString text = i18n("Building Atoll %1. This takes a few minutes.", m_latestVersion);
    setState(u"building"_s, text);
    setPercent(1, i18n("Updating Atoll to %1", m_latestVersion));

    m_process = new QProcess(this);
    m_process->setWorkingDirectory(dir);
    // The user's makepkg.conf may send packages and sources elsewhere; keep
    // everything in the one folder that is wiped before every update.
    QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
    environment.insert(u"PKGDEST"_s, dir);
    environment.insert(u"SRCDEST"_s, dir);
    environment.insert(u"SRCPKGDEST"_s, dir);
    environment.insert(u"LOGDEST"_s, dir);
    environment.insert(u"BUILDDIR"_s, dir + u"/build"_s);
    m_process->setProcessEnvironment(environment);
    m_process->setProcessChannelMode(QProcess::MergedChannels);
    m_log = new QFile(dir + u"/build.log"_s, this);
    m_log->open(QIODevice::WriteOnly);
    connect(m_process, &QProcess::readyReadStandardOutput, this, &Updater::onBuildOutput);
    connect(m_process, &QProcess::finished, this, [this, dir](int code, QProcess::ExitStatus status) {
        onBuildOutput();
        delete m_log;
        m_log = nullptr;
        m_pendingOutput.clear();
        m_process->deleteLater();
        m_process = nullptr;
        if (status != QProcess::NormalExit || code != 0) {
            const QString error = lastError(dir + u"/build.log"_s);
            fail(i18n("The build failed: %1 (log: %2/build.log)", error, dir));
            Q_EMIT announce(u"dialog-error"_s, i18n("The Atoll update failed to build."));
            return;
        }
        const QStringList packages = QDir(dir).entryList({u"%1-*.pkg.tar.*"_s.arg(PackageName)}, QDir::Files);
        for (const QString &name : packages) {
            if (!name.startsWith(PackageName + u"-debug-"_s) && !name.endsWith(u".sig"_s)) {
                installPackage(dir + u'/' + name);
                return;
            }
        }
        fail(i18n("The build finished but left no package in %1.", dir));
    });
    // Low priority, so a build never takes the frames from a game or a video.
    m_process->start(u"nice"_s, {u"-n"_s, u"10"_s, u"makepkg"_s, u"--force"_s, u"--cleanbuild"_s, u"--noconfirm"_s});
}

void Updater::installPackage(const QString &package)
{
    const QString text = i18n("Atoll %1 is built. Enter your password to install it.", m_latestVersion);
    setState(u"installing"_s, text);
    setPercent(94, text);

    const QString log = workDir() + u"/install.log"_s;
    m_process = new QProcess(this);
    m_process->setProcessChannelMode(QProcess::MergedChannels);
    m_process->setStandardOutputFile(log);
    connect(m_process, &QProcess::finished, this, [this, log](int code, QProcess::ExitStatus status) {
        m_process->deleteLater();
        m_process = nullptr;
        if (status == QProcess::NormalExit && (code == PkexecDismissed || code == PkexecNotAuthorized)) {
            fail(i18n("Not installed: the password was not given. Update again when you are ready."));
            return;
        }
        if (status != QProcess::NormalExit || code != 0) {
            fail(i18n("pacman could not install it: %1", lastError(log)));
            Q_EMIT announce(u"dialog-error"_s, i18n("The Atoll update could not be installed."));
            return;
        }
        delete m_lock;
        m_lock = nullptr;
        const QString done = i18n("Updated to Atoll %1. Restarting…", m_latestVersion);
        setState(u"upToDate"_s, done);
        setPercent(100, done);
        // Long enough for the island to show that it worked before it goes.
        QTimer::singleShot(2000, this, &Updater::restartIsland);
    });
    m_process->start(u"pkexec"_s, {u"pacman"_s, u"-U"_s, u"--noconfirm"_s, package});
}

void Updater::restartIsland()
{
    const bool islandProcess = m_timer != nullptr;
    const bool service = runQuietly(u"systemctl"_s, {u"--user"_s, u"is-enabled"_s, u"--quiet"_s, u"atoll.service"_s});
    if (service) {
        // --no-block, or systemctl would wait on the very process that is about to be stopped.
        QProcess::startDetached(u"systemctl"_s, {u"--user"_s, u"restart"_s, u"--no-block"_s, u"atoll.service"_s});
        if (islandProcess && ownUnit() != u"atoll.service"_s) {
            QCoreApplication::quit();
        }
        return;
    }
    if (islandProcess) {
        // The new island waits for the bus name this one gives up on the way out.
        QProcess::startDetached(QCoreApplication::applicationFilePath(), {});
        QCoreApplication::quit();
    } else {
        QProcess::startDetached(QCoreApplication::applicationFilePath(), {u"--quit"_s});
        QTimer::singleShot(1000, this, [] {
            QProcess::startDetached(QCoreApplication::applicationFilePath(), {});
        });
    }
}
