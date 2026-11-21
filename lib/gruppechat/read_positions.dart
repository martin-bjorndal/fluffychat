// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/gruppechat/polls.dart';
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
  Iterable<(String, String)> wrote = const [],
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
  for (final (userId, eventId) in wrote) {
    final index = indexOf[eventId];
    if (index != null && readers.contains(userId)) readTo(userId, index);
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
}) => _readPositions(timeline, threadId, expandedEventIds).positions;

/// [gruppechatReadPositions], with the order of the event IDs they were
/// worked out in ([gruppechatTimelineOrder]).
({List<String> order, Map<String, List<String>> positions}) _readPositions(
  Timeline timeline,
  String? threadId,
  Set<String> expandedEventIds,
) {
  final room = timeline.room;

  // The same messages, collapsed state events aside, that the chat list
  // shows, in its order: polls at their newest vote (polls.dart)
  final (:visible, :moved, :order) = _chatOrder(timeline, threadId);
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
  // Starting a poll is having read up to where it was started, and voting
  // in it is having read up to where it now is
  final wrote = <(String, String)>[];
  for (final MapEntry(key: pollId, value: poll) in moved.entries) {
    if (shown.containsKey(pollId)) shown[pollId] = '';
    wrote.add((poll.senderId, _wasHere(pollId)));
  }
  for (final event in timeline.events) {
    if (event.type == PollEventContent.responseType &&
        !event.redacted &&
        moved.containsKey(event.relationshipEventId)) {
      wrote.add((event.senderId, event.eventId));
    }
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

  final positions = readPositions(
    timeline: order,
    shown: shown,
    receipts: [
      for (final source in sources)
        for (final MapEntry(key: userId, value: receipt)
            in source.otherUsers.entries)
          if (present(userId))
            (
              userId,
              moved.containsKey(receipt.eventId)
                  ? _wasHere(receipt.eventId)
                  : receipt.eventId,
            ),
    ],
    wrote: wrote,
    ownUserId: room.client.userID,
  );
  return (order: order, positions: positions);
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
  // A poll that moved down has been read by those who read past its place
  var index = timeline.indexOf(_wasHere(eventId));
  if (index < 0) index = timeline.indexOf(eventId);
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
}) {
  final (:order, :positions) = _readPositions(
    timeline,
    threadId,
    expandedEventIds,
  );
  return readersOf(
    event.eventId,
    timeline: order,
    positions: positions,
    senderId: event.senderId,
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

/// Stands in for a poll that moved down in the chat, where it was started.
String _wasHere(String pollId) => '$pollId~';

/// The IDs of [events] (newest first) in the order the chat list shows
/// them: each poll in [moved] right after the vote it now stands at, and in
/// its old place a stand-in ([_wasHere]) that a receipt on the poll goes to,
/// as it was read where it was.
List<String> _inShownOrder(List<Event> events, MovedPolls moved) {
  final atVote = <String, List<String>>{};
  for (final MapEntry(key: pollId, value: vote) in moved.entries) {
    (atVote[vote.eventId] ??= []).add(pollId);
  }
  return [
    for (final event in events) ...[
      moved.containsKey(event.eventId)
          ? _wasHere(event.eventId)
          : event.eventId,
      ...?atVote[event.eventId],
    ],
  ];
}

/// The loaded event IDs of [timeline] in the order the read positions are
/// worked out in, for [readersOf].
List<String> gruppechatTimelineOrder(Timeline timeline, {String? threadId}) =>
    _chatOrder(timeline, threadId).order;

/// What the chat list shows of [timeline], the polls in it that moved down,
/// and all loaded event IDs in that order ([_inShownOrder]).
({List<Event> visible, MovedPolls moved, List<String> order}) _chatOrder(
  Timeline timeline,
  String? threadId,
) {
  final moved = <String, Event>{};
  final visible = pollsAtNewestVote(
    timeline.events.filterByVisibleInGui(threadId: threadId),
    timeline,
    moved: moved,
  );
  return (
    visible: visible,
    moved: moved,
    order: _inShownOrder(timeline.events, moved),
  );
}
