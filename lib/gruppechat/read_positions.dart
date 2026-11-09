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
/// Writing something counts as having read up to it, since apps don't send
/// a receipt for their own messages; otherwise someone who just wrote would
/// stay above their own message. That only moves people who send receipts,
/// so someone who turned off read receipts isn't shown at all.
///
/// A receipt can point at something the list doesn't show, such as a
/// reaction or a thread reply, so the reader moves up to the closest shown
/// message above it. [ownUserId] is never shown. Receipts for events that
/// aren't loaded are left out.
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

  final readers = <String>{};
  final readUpTo = <String, int>{};
  void readTo(String userId, int index) {
    final known = readUpTo[userId];
    if (known == null || index < known) readUpTo[userId] = index;
  }

  for (final (userId, eventId) in receipts) {
    if (userId == ownUserId) continue;
    readers.add(userId);
    final index = indexOf[eventId];
    if (index != null) readTo(userId, index);
  }
  for (var i = 0; i < timeline.length; i++) {
    final sender = shown[timeline[i]];
    if (sender != null && readers.contains(sender)) readTo(sender, i);
  }

  final positions = <String, List<String>>{};
  for (final MapEntry(key: userId, value: start) in readUpTo.entries) {
    for (var i = start; i < timeline.length; i++) {
      final eventId = timeline[i];
      if (!shown.containsKey(eventId)) continue;
      (positions[eventId] ??= []).add(userId);
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

  final hasLeft = <String, bool>{};
  bool present(String userId) =>
      !hasLeft.putIfAbsent(userId, () => _hasLeft(room, userId));

  return readPositions(
    timeline: [for (final event in events) event.eventId],
    shown: shown,
    receipts: [
      for (final source in sources)
        for (final MapEntry(key: userId, value: receipt)
            in source.otherUsers.entries)
          if (present(userId)) (userId, receipt.eventId),
    ],
    ownUserId: room.client.userID,
  );
}

/// Everyone who has read [eventId]: whose read position, from
/// [readPositions], is at that message or newer in [timeline] (newest
/// first), in no particular order. [senderId], who wrote it, isn't
/// counted, as in Messenger.
List<String> readersOf(
  String eventId, {
  required List<String> timeline,
  required Map<String, List<String>> positions,
  String? senderId,
}) {
  final index = timeline.indexOf(eventId);
  if (index < 0) return [];
  return [
    for (var i = 0; i <= index; i++) ...?positions[timeline[i]],
  ].where((userId) => userId != senderId).toList();
}

/// Everyone who has read [event], from the read positions the chat shows
/// (see [gruppechatReadPositions] for the arguments). People who left and
/// people who send no read receipts aren't among them.
List<String> gruppechatReadersOf({
  required Timeline timeline,
  required Event event,
  String? threadId,
  Set<String> expandedEventIds = const {},
}) => readersOf(
  event.eventId,
  timeline: [for (final event in timeline.events) event.eventId],
  positions: gruppechatReadPositions(
    timeline: timeline,
    threadId: threadId,
    expandedEventIds: expandedEventIds,
  ),
  senderId: event.senderId,
);

bool _hasLeft(Room room, String userId) {
  final membership = room
      .getState(EventTypes.RoomMember, userId)
      ?.content
      .tryGet<String>('membership');
  return membership == Membership.leave.name ||
      membership == Membership.ban.name;
}
