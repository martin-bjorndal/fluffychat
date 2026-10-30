// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'package:matrix/matrix.dart';

/// Where each reader's read position is shown: the readers' user IDs, keyed
/// by the ID of the message to show them under.
///
/// [timeline] lists every loaded event ID, newest first. [shown] maps the
/// messages the chat list shows to their senders. [receipts] are read
/// receipts as (user ID, event ID) pairs; when a user has several, the one
/// furthest down the chat counts.
///
/// A receipt can point at something the list doesn't show, such as a
/// reaction or a thread reply, so the reader moves up to the closest shown
/// message above it. Readers aren't shown under their own messages, the same
/// as FluffyChat's "seen by" row, and [ownUserId] is never shown. Receipts
/// for events that aren't loaded are left out.
Map<String, List<String>> readPositions({
  required List<String> timeline,
  required Map<String, String> shown,
  required Iterable<(String, String)> receipts,
  String? ownUserId,
}) {
  final indexOf = <String, int>{};
  for (var i = 0; i < timeline.length; i++) {
    indexOf.putIfAbsent(timeline[i], () => i);
  }

  final readUpTo = <String, int>{};
  for (final (userId, eventId) in receipts) {
    if (userId == ownUserId) continue;
    final index = indexOf[eventId];
    if (index == null) continue;
    final known = readUpTo[userId];
    if (known == null || index < known) readUpTo[userId] = index;
  }

  final positions = <String, List<String>>{};
  for (final MapEntry(key: userId, value: start) in readUpTo.entries) {
    for (var i = start; i < timeline.length; i++) {
      final eventId = timeline[i];
      final sender = shown[eventId];
      if (sender == null) continue;
      if (sender != userId) (positions[eventId] ??= []).add(userId);
      break;
    }
  }
  for (final readers in positions.values) {
    readers.sort();
  }
  return positions;
}

/// Everyone else's read position in [timeline], as [readPositions] works it
/// out for the messages the chat list shows. In a thread ([threadId]), the
/// receipts sent inside that thread count; otherwise those for the main chat.
Map<String, List<String>> gruppechatReadPositions({
  required Timeline timeline,
  String? threadId,
  Set<String> expandedEventIds = const {},
}) {
  final room = timeline.room;
  final events = timeline.events;

  // The same messages, collapsed state events aside, that the chat list shows.
  final visible = events.filterByVisibleInGui(threadId: threadId);
  final shown = <String, String>{};
  for (var i = 0; i < visible.length; i++) {
    final event = visible[i];
    final newer = i > 0 ? visible[i - 1] : null;
    final collapsed =
        event.isCollapsedState &&
        newer?.isCollapsedState == true &&
        !expandedEventIds.contains(event.eventId);
    if (!collapsed) shown[event.eventId] = event.senderId;
  }

  final receiptState = room.receiptState;
  final mainThread = receiptState.mainThread;
  final thread = threadId == null ? null : receiptState.byThread[threadId];
  final sources = threadId == null
      ? [receiptState.global, ?mainThread]
      : [?thread];

  return readPositions(
    timeline: [for (final event in events) event.eventId],
    shown: shown,
    receipts: [
      for (final source in sources)
        for (final MapEntry(key: userId, value: receipt)
            in source.otherUsers.entries)
          if (!_hasLeft(room, userId)) (userId, receipt.eventId),
    ],
    ownUserId: room.client.userID,
  );
}

bool _hasLeft(Room room, String userId) {
  final membership = room
      .getState(EventTypes.RoomMember, userId)
      ?.content
      .tryGet<String>('membership');
  return membership == Membership.leave.name ||
      membership == Membership.ban.name;
}
