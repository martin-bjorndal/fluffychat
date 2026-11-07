// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/gruppechat/bubbles.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/push_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:matrix/matrix.dart';

/// The id of the notification for messages in [roomId] on this phone, as
/// lib/utils/push_helper.dart shows it.
int chatNotificationId(Client client, String roomId) =>
    '${client.clientName}_$roomId'.hashCode;

/// Clears the notification of a chat the person has on screen, so it goes
/// away however they got to the chat, not only by tapping it. A bubble's
/// notification is only taken out of the shade, which keeps the bubble.
///
/// Before 1.1.17 a notification only went when tapped, or when the server
/// later pushed that the chat had been read.
Future<void> clearChatNotification(
  Room room, {
  required L10n l10n,
  FlutterLocalNotificationsPlugin? plugin,
}) async {
  // The web app's notifications are the browser's
  // (lib/widgets/local_notifications_extension.dart)
  if (kIsWeb) return;
  plugin ??= FlutterLocalNotificationsPlugin();
  final client = room.client;
  final id = chatNotificationId(client, room.id);
  try {
    final shown = await plugin.getActiveNotifications();
    if (!shown.any((notification) => notification.id == id)) return;
    await GruppechatBubbles.dismiss(plugin, id);
    if (PlatformInfos.isAndroid) {
      await updateSummaryNotification(
        flutterLocalNotificationsPlugin: plugin,
        clientName: client.clientName,
        l10n: l10n,
      );
    }
  } catch (e, s) {
    Logs().w('Could not clear the notification of ${room.id}', e, s);
  }
}
