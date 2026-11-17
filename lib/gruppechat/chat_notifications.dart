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
///
/// The push helper uses it for every push, from the client that fetched it.
/// Before 1.1.39 it took the account from the push itself, which a push
/// through Firebase or UnifiedPush doesn't name: each message then replaced
/// the last in a notification of another id, which the app didn't clear.
int chatNotificationId(Client client, String roomId) =>
    '${client.clientName}_$roomId'.hashCode;

/// The messages the chat notification [id] shows now on Android, which the
/// push helper adds the new message to, or null without one.
Future<MessagingStyleInformation?> shownChatMessages(
  FlutterLocalNotificationsPlugin plugin,
  int id,
) async {
  final android = plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  if (android == null) return null;
  try {
    return await android.getActiveNotificationMessagingStyle(id: id);
  } catch (e, s) {
    // The new message is still shown, on its own
    Logs().w('Could not get the messages of notification $id', e, s);
    return null;
  }
}

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
/// any more: read in the app, on another device, or by answering. With
/// [roomIds], only those chats' notifications.
Future<void> clearReadChatNotifications(
  Client client, {
  L10n? l10n,
  FlutterLocalNotificationsPlugin? plugin,
  Set<String>? roomIds,
}) async {
  if (kIsWeb) return;
  plugin ??= FlutterLocalNotificationsPlugin();
  try {
    final shown = await plugin.getActiveNotifications();
    final rooms = roomIds == null
        ? client.rooms
        : roomIds.map(client.getRoomById).nonNulls.toList();
    var cleared = false;
    for (final notification in shown) {
      if (notification.groupKey != client.clientName) continue;
      final room = rooms.firstWhereOrNull(
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

/// While the app is on screen, clears a chat's notification as soon as
/// [client] learns the chat is read: on another device, in a bubble, or in
/// the app just after the push had come. Only chats in the sync are looked at,
/// so a notification for a message the app hasn't synced yet stays.
///
/// Before 1.1.38 such notifications stayed in the shade until the app left
/// the screen and came back.
class ReadChatNotificationsWatcher {
  final Client client;
  final L10n? l10n;
  final FlutterLocalNotificationsPlugin? plugin;
  StreamSubscription<SyncUpdate>? _subscription;
  final _pending = <String>{};
  bool _running = false;

  ReadChatNotificationsWatcher(this.client, {this.l10n, this.plugin});

  void start() {
    _subscription ??= client.onSync.stream.listen(_synced);
  }

  void cancel() {
    _subscription?.cancel();
    _subscription = null;
    _pending.clear();
  }

  void _synced(SyncUpdate update) {
    // Off the screen, the push helper looks after the shade
    if (!clientIsSyncing(client)) return;
    final joined = update.rooms?.join;
    if (joined == null) return;
    // Chats still unread are skipped here, without asking the shade
    final read = [
      for (final MapEntry(key: roomId, value: room) in joined.entries)
        if (_mayBeRead(room) &&
            client.getRoomById(roomId)?.isUnreadOrInvited == false)
          roomId,
    ];
    if (read.isEmpty) return;
    _pending.addAll(read);
    _clear();
  }

  /// Whether [update] can make its chat read: a read receipt or message of
  /// the person's own, a change to the chat's account data (marked unread
  /// or not), or the server counting nothing unread (a message deleted or
  /// gone). Someone else typing doesn't, and must not clear a notification
  /// for a message the app hasn't synced yet.
  bool _mayBeRead(JoinedRoomUpdate update) {
    final ownId = client.userID;
    if (update.unreadNotifications?.notificationCount == 0) return true;
    if (update.accountData?.isNotEmpty ?? false) return true;
    if (update.timeline?.events?.any((e) => e.senderId == ownId) ?? false) {
      return true;
    }
    return update.ephemeral?.any(
          (e) =>
              e.type == 'm.receipt' &&
              ReceiptEventContent.fromJson(e.content).receipts.values.any(
                (byType) =>
                    byType.values.any((users) => users.containsKey(ownId)),
              ),
        ) ??
        false;
  }

  /// One pass at a time; rooms synced meanwhile get the next one.
  Future<void> _clear() async {
    if (_running) return;
    _running = true;
    try {
      while (_pending.isNotEmpty && _subscription != null) {
        final roomIds = {..._pending};
        _pending.clear();
        await clearReadChatNotifications(
          client,
          l10n: l10n,
          plugin: plugin,
          roomIds: roomIds,
        );
      }
    } finally {
      _running = false;
    }
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
