// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/gruppechat/bubbles.dart';
import 'package:fluffychat/gruppechat/matrix_group.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/notification_avatar_extension.dart';
import 'package:fluffychat/utils/push_helper.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// "Show as bubble" in a chat's menu, and "Open in app" in a bubble.
List<PopupMenuEntry<T>> gruppechatBubbleMenuItems<T>(
  BuildContext context,
  Room room,
) {
  if (!GruppechatBubbles.supported) return const [];
  final l10n = L10n.of(context);
  if (GruppechatBubbles.active) {
    return [
      PopupMenuItem<T>(
        onTap: () => GruppechatBubbles.openInApp(room.id),
        child: Row(
          children: [
            const Icon(Icons.open_in_new_outlined),
            const SizedBox(width: 12),
            Text(l10n.gruppechatOpenInApp),
          ],
        ),
      ),
    ];
  }
  return [
    PopupMenuItem<T>(
      onTap: () => showRoomAsBubble(context, room),
      child: Row(
        children: [
          const Icon(Icons.bubble_chart_outlined),
          const SizedBox(width: 12),
          Text(l10n.gruppechatShowAsBubble),
        ],
      ),
    ),
  ];
}

/// Opens [room] in a bubble. Turns chat bubbles on, since without them the
/// next message would close the bubble, and asks the person to allow
/// bubbles in Android's settings if they aren't yet.
Future<void> showRoomAsBubble(BuildContext context, Room room) async {
  final l10n = L10n.of(context);
  final status = await GruppechatBubbles.status();
  if (!status.supported) return;
  await AppSettings.gruppechatBubbles.setItem(true);
  if (!await GruppechatBubbles.canBubble(room.id)) {
    if (!context.mounted) return;
    final result = await showOkCancelAlertDialog(
      context: context,
      title: l10n.gruppechatAllowBubbles,
      message: switch (bubbleHint(status)) {
        BubbleHint.notificationsOff => l10n.gruppechatNotificationsOffMessage,
        BubbleHint.bubblesOff => l10n.gruppechatBubblesOffMessage,
        _ => l10n.gruppechatAllowBubblesMessage,
      },
      okLabel: l10n.gruppechatOpenSettings,
      cancelLabel: l10n.cancel,
    );
    if (result == OkCancelResult.ok) {
      await GruppechatBubbles.openSettings(
        bubbles: bubbleHint(status) != BubbleHint.notificationsOff,
      );
    }
    return;
  }

  final client = room.client;
  final title = room.getLocalizedDisplayname(MatrixLocals(l10n));
  final icon =
      await client.tryDownloadNotificationAvatar(room.avatar) ??
      await GruppechatBubbles.placeholderAvatar(title);
  // A bubble needs a conversation shortcut, as notifications get
  await setRoomShortcut(room, title, icon);
  final lastEvent = room.lastEvent;
  await GruppechatBubbles.openBubble(
    // As push_helper.dart numbers a room's notification
    id: '${client.clientName}_${room.id}'.hashCode,
    roomId: room.id,
    icon: icon,
    payload: FluffyChatPushPayload(
      client.clientName,
      room.id,
      lastEvent?.eventId,
    ).toString(),
    details: () => _quietNotification(room, title, l10n),
  );
}

/// A quiet notification for a chat that has none, showing its last message,
/// for its bubble to belong to. The next message replaces it with a
/// regular one.
Future<AndroidNotificationDetails> _quietNotification(
  Room room,
  String title,
  L10n l10n,
) async {
  final client = room.client;
  final ownUser = room.unsafeGetUserFromMemoryOrFallback(client.userID!);
  final ownAvatar = await client.tryDownloadNotificationAvatar(
    ownUser.avatarUrl,
  );
  final lastEvent = room.lastEvent;
  final messages = <Message>[
    if (lastEvent != null)
      Message(
        lastEvent.type == EventTypes.Encrypted
            ? l10n.newMessageInFluffyChat
            : await lastEvent.calcLocalizedBody(
                MatrixLocals(l10n),
                plaintextBody: true,
                withSenderNamePrefix: false,
                hideReply: true,
                hideEdit: true,
                removeMarkdown: true,
              ),
        lastEvent.originServerTs,
        // A message without a person is the person's own
        lastEvent.senderId == client.userID
            ? null
            : Person(
                key: lastEvent.senderId,
                name: lastEvent.senderFromMemoryOrFallback.groupDisplayname(),
              ),
      ),
  ];
  return AndroidNotificationDetails(
    AppConfig.pushNotificationsChannelId,
    l10n.incomingMessages,
    category: AndroidNotificationCategory.message,
    shortcutId: room.id,
    styleInformation: MessagingStyleInformation(
      Person(
        key: client.userID,
        name: ownUser.calcDisplayname(),
        icon: ownAvatar == null ? null : ByteArrayAndroidIcon(ownAvatar),
      ),
      conversationTitle: room.isDirectChat ? null : title,
      groupConversation: !room.isDirectChat,
      messages: messages,
    ),
    importance: Importance.high,
    priority: Priority.max,
    groupKey: client.clientName,
    silent: true,
  );
}

/// The chat bubble settings on the notifications page, on Android 11 and
/// newer.
class GruppechatBubbleSettings extends StatefulWidget {
  const GruppechatBubbleSettings({super.key});

  @override
  State<GruppechatBubbleSettings> createState() =>
      _GruppechatBubbleSettingsState();
}

class _GruppechatBubbleSettingsState extends State<GruppechatBubbleSettings> {
  BubbleStatus? _status;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // The person may change Android's settings and come back
    _lifecycle = AppLifecycleListener(onResume: _load);
    _load();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final status = await GruppechatBubbles.status();
    if (mounted) setState(() => _status = status);
  }

  Future<void> _toggle(bool on) async {
    await AppSettings.gruppechatBubbles.setItem(on);
    if (!on) await GruppechatBubbles.removeBubbles();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    if (status == null || !status.supported) return const SizedBox.shrink();
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final on = AppSettings.gruppechatBubbles.value;
    final hint = on ? bubbleHint(status) : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          title: Text(
            l10n.gruppechatBubbles,
            style: TextStyle(
              color: theme.colorScheme.secondary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SwitchListTile.adaptive(
          value: on,
          title: Text(l10n.gruppechatShowChatsAsBubbles),
          subtitle: Text(l10n.gruppechatBubblesDescription),
          onChanged: _toggle,
        ),
        if (hint != null)
          ListTile(
            leading: const Icon(Icons.info_outlined),
            title: Text(switch (hint) {
              BubbleHint.notificationsOff => l10n.gruppechatNotificationsOff,
              BubbleHint.bubblesOff => l10n.gruppechatBubblesTurnedOff,
              BubbleHint.notAllowed => l10n.gruppechatBubblesNotAllowed,
              BubbleHint.onlySelected => l10n.gruppechatBubblesOnlySelected,
            }),
            subtitle: Text(switch (hint) {
              BubbleHint.notificationsOff =>
                l10n.gruppechatNotificationsOffHint,
              BubbleHint.bubblesOff => l10n.gruppechatBubblesTurnOnHint,
              BubbleHint.notAllowed => l10n.gruppechatBubblesAllowHint,
              BubbleHint.onlySelected => l10n.gruppechatBubblesSelectedHint,
            }),
            onTap: () => GruppechatBubbles.openSettings(
              bubbles: hint != BubbleHint.notificationsOff,
            ),
          ),
        Divider(color: theme.dividerColor),
      ],
    );
  }
}
