// SPDX-FileCopyrightText: 2026 The Atoll contributors
// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import Atoll

/**
 * A single notification, morphed into. The island mirrors what the real
 * notification daemon received, so this is a second, glanceable surface rather
 * than a replacement popup.
 */
Item {
    id: view

    property var notification: ({})
    property bool replying: false

    readonly property bool critical: (notification.urgency ?? 1) >= 2
    readonly property string image: notification.image ?? ""
    readonly property bool hasProgress: (notification.progress ?? -1) >= 0
    readonly property bool hasReplyOption: (Cfg.notifications.quickReply ?? true)
                                         && ((notification.hasReply ?? false) || (notification.isKdeConnect ?? false))
    readonly property bool isVesktop: (notification.isVesktop ?? false)

    signal dismissRequested()
    signal replyActiveChanged(bool active)

    implicitHeight: replying ? 116 : 74
    // Sized from what the text needs, never from contentCol: that column is anchored to this view, so its
    // implicitWidth follows our own width and the island would keep creeping wider while it is shown.
    readonly property real textWidth: Math.min(320, Math.max(180, appLabel.implicitWidth, summary.implicitWidth,
                                                             body.implicitWidth))
    implicitWidth: Math.min(Cfg.maxWidth,
                            Math.max(replying ? 420 : 320,
                                     40 + 12 + textWidth + (actionArea.visible ? actionArea.width + 12 : 0)
                                     + Math.max(15, Theme.edgeInset) * 2))

    onNotificationChanged: {
        replying = false
    }

    onReplyingChanged: {
        view.replyActiveChanged(replying)
        if (replying) {
            Qt.callLater(() => replyInput.forceActiveFocus())
        }
    }

    Column {
        id: contentCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Math.max(15, Theme.edgeInset)
        anchors.rightMargin: Math.max(15, Theme.edgeInset)
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        Row {
            id: topRow
            width: parent.width
            spacing: 12

            Item {
                width: 40
                height: 40
                anchors.verticalCenter: parent.verticalCenter

                AlbumArt {
                    anchors.fill: parent
                    visible: view.image.length > 0
                    source: view.image
                    cornerRadius: 10
                }

                Rectangle {
                    anchors.fill: parent
                    visible: view.image.length === 0
                    radius: 10
                    color: Qt.rgba(1, 1, 1, 0.08)

                    IconImage {
                        anchors.centerIn: parent
                        width: 22
                        height: 22
                        names: [view.notification.appIcon ?? "",
                                view.notification.desktopEntry ?? "",
                                "dialog-information"]
                    }
                }

                Rectangle {
                    visible: view.critical
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: -2
                    width: 10
                    height: 10
                    radius: 5
                    color: Theme.critical
                    border.width: 2
                    border.color: Theme.background
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 40 - 12 - (actionArea.visible ? actionArea.width + 12 : 0)
                spacing: 2

                Text {
                    id: appLabel
                    width: parent.width
                    text: view.notification.appName ?? ""
                    visible: text.length > 0
                    color: view.critical ? Theme.critical : Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.size(10)
                    font.weight: Font.DemiBold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 0.6
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                Text {
                    id: summary
                    width: parent.width
                    text: view.notification.summary ?? ""
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.size(13)
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                Text {
                    id: body
                    width: parent.width
                    text: (view.notification.body ?? "").replace(/<[^>]*>/g, "")
                    visible: text.length > 0 && !view.hasProgress && !view.replying
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.size(11)
                    wrapMode: Text.WordWrap
                    elide: Text.ElideRight
                    maximumLineCount: Cfg.notifications.maxBodyLines ?? 2
                }

                LevelBar {
                    visible: view.hasProgress
                    width: parent.width
                    height: 5
                    value: (view.notification.progress ?? 0) / 100
                    fillColor: Theme.accent
                }
            }

            Item {
                id: actionArea
                anchors.verticalCenter: parent.verticalCenter
                width: view.replying ? cancelBtn.width : (replyPill.visible ? replyPill.width : (vesktopPill.visible ? vesktopPill.width : 0))
                height: 28
                visible: view.replying || replyPill.visible || vesktopPill.visible

                // Cancel button when replying
                RoundButton {
                    id: cancelBtn
                    anchors.centerIn: parent
                    visible: view.replying
                    width: 24
                    height: 24
                    icon: ["window-close"]
                    onClicked: {
                        view.replying = false
                    }
                }

                // Quick reply trigger pill (KDE Connect / standard FreeDesktop reply)
                Rectangle {
                    id: replyPill
                    visible: !view.replying && view.hasReplyOption
                    anchors.centerIn: parent
                    height: 26
                    width: replyRow.implicitWidth + 18
                    radius: 13
                    color: replyPillHover.hovered ? Theme.tint(0.2) : Theme.tint(0.1)
                    border.width: 1
                    border.color: replyPillHover.hovered ? Theme.accent : Theme.borderColor

                    Row {
                        id: replyRow
                        anchors.centerIn: parent
                        spacing: 5
                        IconImage {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 13
                            height: 13
                            names: ["mail-reply-sender", "edit-undo", "go-next"]
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("Reply")
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.size(11)
                            font.weight: Font.DemiBold
                        }
                    }

                    HoverHandler {
                        id: replyPillHover
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            view.replying = true
                        }
                    }
                }

                // Quick reply pill for Vesktop / Discord (raises conversation)
                Rectangle {
                    id: vesktopPill
                    visible: !view.replying && !view.hasReplyOption && view.isVesktop
                    anchors.centerIn: parent
                    height: 26
                    width: vesktopRow.implicitWidth + 18
                    radius: 13
                    color: vesktopPillHover.hovered ? Theme.tint(0.2) : Theme.tint(0.1)
                    border.width: 1
                    border.color: vesktopPillHover.hovered ? Theme.accent : Theme.borderColor

                    Row {
                        id: vesktopRow
                        anchors.centerIn: parent
                        spacing: 5
                        IconImage {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 13
                            height: 13
                            names: ["mail-reply-sender", "edit-undo", "vesktop", "discord"]
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("Reply")
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.size(11)
                            font.weight: Font.DemiBold
                        }
                    }

                    HoverHandler {
                        id: vesktopPillHover
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            App.notifications.open(view.notification.uid ?? 0)
                            view.dismissRequested()
                        }
                    }
                }
            }
        }

        // Inline reply text box
        Rectangle {
            id: replyBox
            visible: view.replying
            width: parent.width
            height: 36
            radius: 18
            color: Qt.rgba(1, 1, 1, replyInput.activeFocus ? 0.12 : 0.07)
            border.width: 1
            border.color: replyInput.activeFocus ? Theme.accent : Theme.borderColor

            Row {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 6
                spacing: 8

                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - sendBtn.width - 14
                    height: parent.height

                    TextInput {
                        id: replyInput
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.foreground
                        selectionColor: Theme.accent
                        selectedTextColor: Theme.background
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.size(12)
                        selectByMouse: true
                        clip: true

                        onAccepted: {
                            if (text.trim().length > 0) {
                                App.notifications.sendReply(view.notification.uid ?? 0, text.trim())
                            }
                            view.replying = false
                            view.dismissRequested()
                        }

                        Keys.onEscapePressed: {
                            view.replying = false
                        }
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: view.notification.replyPlaceholder || (view.notification.isKdeConnect ? qsTr("Reply via phone...") : qsTr("Type a reply..."))
                        color: Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.size(12)
                        visible: replyInput.text.length === 0 && !replyInput.inputMethodComposing
                    }
                }

                RoundButton {
                    id: sendBtn
                    anchors.verticalCenter: parent.verticalCenter
                    width: 26
                    height: 26
                    icon: ["arrow-up", "mail-send", "go-next"]
                    enabled: replyInput.text.trim().length > 0
                    opacity: enabled ? 1.0 : 0.4
                    onClicked: {
                        if (replyInput.text.trim().length > 0) {
                            App.notifications.sendReply(view.notification.uid ?? 0, replyInput.text.trim())
                        }
                        view.replying = false
                        view.dismissRequested()
                    }
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        enabled: !view.replying
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) {
                App.notifications.close(view.notification.uid ?? 0)
            } else {
                // Hand the app its default action and bring it forward, the
                // way a Plasma popup does.
                App.notifications.open(view.notification.uid ?? 0)
            }
            view.dismissRequested()
        }
    }
}
