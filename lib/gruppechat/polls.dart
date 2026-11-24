// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'package:matrix/matrix.dart';

/// The polls that moved down in the chat, by ID, each with the vote it now
/// stands at.
typedef MovedPolls = Map<String, Event>;

/// The events of [timeline] as the chat list shows them, newest first:
/// those shown in the chat (or the thread [threadId]), cut off at
/// [endsAtEventId] while newer ones are held back, with each poll that has
/// been voted in moved down to where its newest vote is ([pollsAtNewestVote]).
/// Moved polls go into [moved].
///
/// The cut is made in time order, as the place it is made at was found, and
/// votes that came with the held-back messages don't move a poll yet, so it
/// doesn't leave the part of the chat someone is reading.
List<Event> shownInChat(
  Timeline timeline, {
  String? threadId,
  String? endsAtEventId,
  String? exceptionEventId,
  MovedPolls? moved,
}) {
  var events = timeline.events.filterByVisibleInGui(
    threadId: threadId,
    exceptionEventId: exceptionEventId,
  );
  final endIndex = endsAtEventId == null
      ? -1
      : events.indexWhere((event) => event.eventId == endsAtEventId);
  final held = endIndex > 0 ? events[endIndex - 1].eventId : null;
  if (endIndex > 0) events = events.sublist(endIndex);
  return pollsAtNewestVote(events, timeline, heldBackFrom: held, moved: moved);
}

/// [events] as the chat shows them (newest first, from `filterByVisibleInGui`
/// on [timeline]'s events), with each poll that has been voted in moved down
/// to where its newest vote is: with no messages after that vote it is at
/// the very bottom, and messages written after it come below it.
///
/// Votes are hidden in the chat, so without this a poll stays far up where
/// it was started. Votes that don't count in the poll don't move it either:
/// deleted ones, own ones that failed to send, and those after the poll was
/// ended. Votes as new as [heldBackFrom], the oldest held-back message, or
/// newer are left for later. Only the order on screen changes; the read
/// marker and the read positions follow it (read_positions.dart).
List<Event> pollsAtNewestVote(
  List<Event> events,
  Timeline timeline, {
  String? heldBackFrom,
  MovedPolls? moved,
}) {
  final polls = {
    for (final e in events)
      if (e.type == PollEventContent.startType && !e.redacted) e.eventId: e,
  };
  if (polls.isEmpty) return events;

  final all = timeline.events;
  final indexOf = <String, int>{
    for (var i = 0; i < all.length; i++) all[i].eventId: i,
  };
  final held = heldBackFrom == null ? null : indexOf[heldBackFrom];
  final newestAllowed = held == null ? 0 : held + 1;

  // Where in the timeline (newest first) each poll's newest vote is, going
  // from the oldest event so that a vote after the end is seen after it
  final newestVote = <String, int>{};
  final ended = <String>{};
  for (var i = all.length - 1; i >= newestAllowed; i--) {
    final event = all[i];
    final poll = polls[event.relationshipEventId];
    if (poll == null || event.redacted || event.status.isError) continue;
    if (_endsPoll(event, poll)) {
      ended.add(poll.eventId);
    } else if (event.type == PollEventContent.responseType &&
        !ended.contains(poll.eventId)) {
      newestVote[poll.eventId] = i;
    }
  }

  final toMove = <(int, Event)>[];
  final rest = <Event>[];
  for (final event in events) {
    final vote = newestVote[event.eventId];
    final at = indexOf[event.eventId];
    if (vote != null && at != null && vote < at) {
      toMove.add((vote, event));
      moved?[event.eventId] = all[vote];
    } else {
      rest.add(event);
    }
  }
  if (toMove.isEmpty) return events;
  toMove.sort((a, b) => a.$1.compareTo(b.$1));

  // Each moved poll goes just before the first event older than its vote
  final result = <Event>[];
  var next = 0;
  for (final event in rest) {
    final at = indexOf[event.eventId] ?? -1;
    while (next < toMove.length && toMove[next].$1 < at) {
      result.add(toMove[next++].$2);
    }
    result.add(event);
  }
  for (; next < toMove.length; next++) {
    result.add(toMove[next].$2);
  }
  return result;
}

/// Whether [event] ends [poll], as the SDK's `getPollHasBeenEnded` counts
/// it (`_getEndPollEvent` in the SDK's poll_event_extension.dart, which
/// isn't public): from the one who started it, or someone allowed to delete
/// messages. Votes after it are told by the order of the timeline.
bool _endsPoll(Event event, Event poll) {
  if (event.content.tryGetMap<String, Object?>(PollEventContent.endType) ==
      null) {
    return false;
  }
  if (event.senderId == poll.senderId) return true;
  final redactLevel =
      poll.room
          .getState(EventTypes.RoomPowerLevels)
          ?.content
          .tryGet<int>('redact') ??
      50;
  return event.senderFromMemoryOrFallback.powerLevel.level >= redactLevel;
}

/// The polls in [timeline] that [userId] hasn't answered yet, newest first,
/// for the banner at the top of the chat (poll_banner.dart). Polls started
/// by [userId], deleted or ended ones, and those in [dismissed] (closed
/// banners, by event ID) don't count, nor those the chat doesn't show (in a
/// thread). A vote that failed to send or was deleted doesn't count as an
/// answer. Only the loaded part of the chat is looked through.
Iterable<Event> unansweredPolls(
  Timeline timeline,
  String userId, {
  Set<String> dismissed = const {},
}) sync* {
  // Only poll starts go through the (costlier) visibility check: this runs
  // on every build of the chat
  final polls = timeline.events
      .where((e) => e.type == PollEventContent.startType)
      .toList()
      .filterByVisibleInGui();
  for (final event in polls) {
    if (event.redacted ||
        event.senderId == userId ||
        dismissed.contains(event.eventId)) {
      continue;
    }
    final live =
        (timeline.aggregatedEvents[event.eventId]?[RelationshipTypes
                    .reference] ??
                const <Event>{})
            .where((e) => !e.redacted && !e.status.isError);
    if (live.any(
      (e) =>
          (e.type == PollEventContent.responseType && e.senderId == userId) ||
          _endsPoll(e, event),
    )) {
      continue;
    }
    // A poll the app can't read shows as a broken bubble, not a banner
    try {
      event.parsedPollEventContent;
    } catch (_) {
      continue;
    }
    yield event;
  }
}

/// The newest of [unansweredPolls], or null.
Event? unansweredPoll(
  Timeline timeline,
  String userId, {
  Set<String> dismissed = const {},
}) => unansweredPolls(timeline, userId, dismissed: dismissed).firstOrNull;

/// Closes the banner: adds every poll in [timeline] that [userId] hasn't
/// answered to [dismissed], so older ones don't show up one after another.
void dismissUnansweredPolls(
  Timeline timeline,
  String userId,
  Set<String> dismissed,
) => dismissed.addAll([
  for (final poll in unansweredPolls(timeline, userId, dismissed: dismissed))
    poll.eventId,
]);

/// Those who chose [answerId], by user ID, from a poll's [responses]
/// (`getPollResponses`): the faces and the count ("1 stemme") under the
/// answer (poll.dart, chat_transcript.dart).
Set<String> pollVoters(Map<String, Set<String>> responses, String answerId) =>
    {
      for (final entry in responses.entries)
        if (entry.value.contains(answerId)) entry.key,
    };

/// The time a chat item counts as for the dates in the chat: a moved poll
/// that of the vote it stands at.
DateTime shownTime(Event event, MovedPolls moved) =>
    moved[event.eventId]?.originServerTs ?? event.originServerTs;

/// Where the "read up to here" line shows in [shown] for the read marker
/// [eventId]. On a poll that has moved down, everything older than the
/// poll's own place has been read, so the line goes to the first of those
/// that stays where it was.
String? readMarkerShownAt(
  List<Event> shown,
  Timeline timeline,
  MovedPolls moved,
  String? eventId,
) {
  if (eventId == null || !moved.containsKey(eventId)) return eventId;
  final all = timeline.events;
  final at = all.indexWhere((e) => e.eventId == eventId);
  if (at < 0) return eventId;
  final shownIds = {
    for (final e in shown)
      if (!moved.containsKey(e.eventId)) e.eventId,
  };
  for (var i = at + 1; i < all.length; i++) {
    if (shownIds.contains(all[i].eventId)) return all[i].eventId;
  }
  return null;
}
