// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:collection/collection.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/gruppechat/chat_notifications.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:matrix/matrix.dart';

// Reading a chat: where the chat page shows what is new, and marking what it
// shows as read (lib/pages/chat/chat.dart).

/// Where the chat page puts its "New messages" line: at the person's read
/// marker, or nowhere ('') when nothing is new.
String newMessagesLineEventId(Room room) {
  final lastEvent = room.lastEvent;
  final lastEventThreadId =
      lastEvent?.relationshipType == RelationshipTypes.thread
      ? lastEvent?.relationshipEventId
      : null;
  return room.hasNewMessages ? lastEventThreadId ?? room.fullyRead : '';
}

/// With more new messages than this, a chat opens with a banner at the top
/// that counts them and jumps up to the first.
const newMessagesForBanner = 5;

/// The banner at the top of a chat, which opens at the newest message: it
/// jumps up to [eventId], where the person stopped reading.
class NewMessagesBanner {
  final String eventId;

  /// How many messages are new, or 0 when the chat only knows where the
  /// person stopped reading, further back than it has loaded.
  final int count;

  const NewMessagesBanner(this.eventId, this.count);
}

/// The banner a chat opens with once [timeline] is loaded, or null when the
/// new messages since [lineEventId] fit on the screen. Loads older messages
/// once to find the line.
Future<NewMessagesBanner?> newMessagesBanner(
  Timeline timeline,
  String lineEventId, {
  String? threadId,
  required int historyCount,
}) async {
  if (lineEventId.isEmpty) return null;
  int position() => timeline.events
      .filterByVisibleInGui(exceptionEventId: lineEventId, threadId: threadId)
      .indexWhere((event) => event.eventId == lineEventId);

  var index = position();
  if (index == -1) {
    await timeline.requestHistory(historyCount: historyCount);
    index = position();
  }
  if (index == -1) return NewMessagesBanner(lineEventId, 0);
  return index > newMessagesForBanner
      ? NewMessagesBanner(lineEventId, index)
      : null;
}

/// The message the chat page puts the person's read marker on while it
/// shows [timeline]: [eventId], or else the newest message that notifies.
/// Null leaves the read marker where it is. [scrolledUp] is whether the
/// person has scrolled up from the newest messages.
///
/// A chat opens at the newest message, so opening it marks it read, also
/// while the banner offers to jump up to the first new message. Until 1.1.17
/// the banner held the read marker back until it was used or closed.
String? readMarkerTarget(
  Room room,
  Timeline timeline, {
  String? eventId,
  required bool scrolledUp,
}) {
  // Only at the newest messages
  if (scrolledUp) return null;

  if (timeline.events.isEmpty) return null;

  // Not on the notice of a call that is going on
  if (_ringsIn(room, timeline.events.first)) return null;

  final latest = eventId == null;
  eventId ??= timeline.events
      .firstWhereOrNull(
        (event) => room.client.pushruleEvaluator.match(event).notify,
      )
      ?.eventId;
  if (latest && (room.hasNewMessages || room.isUnread)) {
    eventId ??= room.lastEvent?.eventId ?? timeline.events.firstOrNull?.eventId;
  }

  // Nothing to mark, or a message still being sent
  if (eventId == null || !eventId.isValidMatrixIdStrict()) return null;

  // Already there
  if (!latest && room.fullyRead == eventId) return null;

  // Nothing is unread
  if (latest && !room.hasNewMessages && room.notificationCount == 0) {
    return null;
  }
  return eventId;
}

/// Whether the menus of the chat list and a group's channel list offer
/// "Mark as read" for [room], and not "Mark as unread": the list shows it
/// unread, with new messages or marked unread.
bool offersMarkRead(Room room) => room.isUnread || room.hasNewMessages;

/// "Mark as read" in the chat list or a group's channel list: puts the read
/// marker on [room]'s newest message, takes away its unread mark, and clears
/// its notification. Not while a call rings in it, as for opening the chat
/// ([readMarkerTarget]): the call's notification stays.
///
/// Before 1.1.39 a group's channel list marked a channel with new messages
/// unread instead, and the chat list only took the mark away, so the
/// messages and the notification stayed unread.
Future<void> markChatRead(
  Room room, {
  required L10n l10n,
  FlutterLocalNotificationsPlugin? plugin,
}) async {
  final last = room.lastEvent;
  final ringing = _ringsIn(room, last);
  final eventId = last?.eventId;
  await Future.wait([
    // Nothing to mark, or a message of hers still being sent
    if (!ringing && eventId != null && eventId.isValidMatrixIdStrict())
      room.setReadMarker(
        eventId,
        mRead: eventId,
        public: AppSettings.sendPublicReadReceipts.value,
      ),
    room.markUnread(false),
    // At once, not on the next sync (ReadChatNotificationsWatcher)
    if (!ringing) clearChatNotification(room, l10n: l10n, plugin: plugin),
  ]);
}

/// Whether [event] is the notice of a call going on in [room]: marking it
/// read would stop the phone ringing.
bool _ringsIn(Room room, Event? event) =>
    room.hasActiveMatrixRtcCall &&
    event?.type == RtcNotificationContent.eventType;
