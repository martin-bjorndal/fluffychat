// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:collection/collection.dart';
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

final _syncPaused = Expando<bool>('sync paused');

/// Turns [client]'s sync loop on or off, as the app does on a phone when it
/// leaves and comes back to the screen (lib/widgets/matrix.dart), and
/// remembers it: while paused, what the client knows of read messages may be
/// old, so the push helper syncs before showing a push.
void setClientSyncing(Client client, bool syncing) {
  client.backgroundSync = syncing;
  _syncPaused[client] = !syncing;
}

/// Whether [client] keeps up with the server by itself, see
/// [setClientSyncing].
bool clientIsSyncing(Client client) => _syncPaused[client] != true;

/// Whether the person has already read [event] in [room]: they sent it, a
/// read receipt of theirs is on it or came after it, or they have written in
/// the chat since. As far as [room] knows, so sync before asking.
bool hasReadEvent(Room room, Event event) {
  final ownId = room.client.userID;
  if (event.senderId == ownId) return true;
  final sent = event.originServerTs.millisecondsSinceEpoch;
  final receipts = room.receiptState;
  // Receipts in the event's own thread, or in the main timeline
  final threadId = event.relationshipType == RelationshipTypes.thread
      ? event.relationshipEventId
      : null;
  final own = [
    receipts.global.latestOwnReceipt,
    threadId == null
        ? receipts.mainThread?.latestOwnReceipt
        : receipts.byThread[threadId]?.latestOwnReceipt,
  ].nonNulls;
  if (own.any((r) => r.eventId == event.eventId || r.ts >= sent)) return true;
  final last = room.lastEvent;
  return last != null &&
      last.senderId == ownId &&
      last.originServerTs.millisecondsSinceEpoch >= sent;
}

/// Whether a push for [event] is too late to show, because the person has
/// read it by now. Then the chat's notification goes too.
///
/// Pushes can come long after the message: Android may hold them back for
/// a phone that sleeps, and the push helper takes seconds to fetch and
/// decrypt one in the background. Before 1.1.18 such a push showed the
/// message again, 20 to 30 minutes after it was read and answered.
///
/// [sync] gets the latest read receipts first, for a client that doesn't
/// sync by itself: in the push helper's background isolate, or while the app
/// is off the screen.
Future<bool> pushIsAlreadyRead(
  Event event, {
  required bool sync,
  required L10n l10n,
  FlutterLocalNotificationsPlugin? plugin,
}) async {
  final client = event.room.client;
  if (sync) {
    try {
      await client.roomsLoading;
      await client.oneShotSync().timeout(const Duration(seconds: 8));
    } catch (e, s) {
      Logs().w('Could not sync before showing a push', e, s);
    }
  }
  final room = client.getRoomById(event.room.id) ?? event.room;
  final read = hasReadEvent(room, event);
  if (read) await clearChatNotification(room, l10n: l10n, plugin: plugin);
  return read;
}

/// Clears the notifications of [client]'s chats that have nothing unread
/// any more: read in the app, on another device, or by answering.
Future<void> clearReadChatNotifications(
  Client client, {
  L10n? l10n,
  FlutterLocalNotificationsPlugin? plugin,
}) async {
  if (kIsWeb) return;
  plugin ??= FlutterLocalNotificationsPlugin();
  try {
    final shown = await plugin.getActiveNotifications();
    var cleared = false;
    for (final notification in shown) {
      if (notification.groupKey != client.clientName) continue;
      final room = client.rooms.firstWhereOrNull(
        (room) => chatNotificationId(client, room.id) == notification.id,
      );
      if (room == null || room.isUnreadOrInvited) continue;
      await GruppechatBubbles.dismiss(plugin, notification.id!);
      cleared = true;
    }
    if (cleared && PlatformInfos.isAndroid) {
      await updateSummaryNotification(
        flutterLocalNotificationsPlugin: plugin,
        clientName: client.clientName,
        l10n: l10n ?? await lookupL10n(PlatformDispatcher.instance.locale),
      );
    }
  } catch (e, s) {
    Logs().w('Could not clear the notifications of read chats', e, s);
  }
}

/// When the app comes back to the screen: once [client] has caught up with
/// the server, the notifications of chats read meanwhile go.
Future<void> clearReadChatNotificationsOnResume(Client client) async {
  if (kIsWeb || !client.isLogged()) return;
  try {
    await client.onSync.stream.first.timeout(const Duration(seconds: 15));
  } on TimeoutException {
    // Clear what the app already knows is read
  }
  await clearReadChatNotifications(client);
}
