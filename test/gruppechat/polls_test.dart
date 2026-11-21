// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// A poll moves down in the chat to where its newest vote is, so nobody has
// to scroll far up to find it (lib/gruppechat/polls.dart).

import 'package:fluffychat/gruppechat/polls.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
// ignore: implementation_imports
import 'package:matrix/src/models/timeline_chunk.dart';

import '../utils/test_client.dart';

void main() {
  late Client client;
  late Room room;
  setUpAll(() async {
    client = await prepareTestClient();
    room = Room(id: '!r:test', client: client);
  });

  var n = 0;
  Event event(
    String id,
    String type,
    Map<String, Object?> content, {
    String sender = '@alice:test',
    EventStatus status = EventStatus.synced,
  }) => Event(
    type: type,
    content: content,
    eventId: '\$$id',
    senderId: sender,
    originServerTs: DateTime(2026, 1, 1, 12, n++),
    status: status,
    room: room,
  );

  Event text(String id) =>
      event(id, EventTypes.Message, {'msgtype': 'm.text', 'body': id});
  Event poll(String id) => event(id, PollEventContent.startType, {
    PollEventContent.startType: {
      'question': {'org.matrix.msc1767.text': 'Når?'},
      'kind': 'org.matrix.msc3381.poll.disclosed',
      'max_selections': 1,
      'answers': [
        {'id': '1', 'org.matrix.msc1767.text': 'Fredag'},
      ],
    },
  });
  Map<String, Object?> relatesTo(String pollId) => {
    'event_id': '\$$pollId',
    'rel_type': RelationshipTypes.reference,
  };
  Event vote(
    String id,
    String pollId, {
    String sender = '@bob:test',
    EventStatus status = EventStatus.synced,
  }) => event(
    id,
    PollEventContent.responseType,
    {
      'm.relates_to': relatesTo(pollId),
      PollEventContent.responseType: {
        'answers': ['1'],
      },
    },
    sender: sender,
    status: status,
  );
  Event end(String id, String pollId, {String sender = '@alice:test'}) => event(
    id,
    PollEventContent.endType,
    {'m.relates_to': relatesTo(pollId), PollEventContent.endType: {}},
    sender: sender,
  );

  Timeline timelineOf(List<Event> oldestFirst) => Timeline(
    room: room,
    chunk: TimelineChunk(events: oldestFirst.reversed.toList()),
  );
  List<String> ids(List<Event> events) =>
      events.map((e) => e.eventId.substring(1)).toList();

  /// The chat as the list shows it, from [oldestFirst] events.
  List<String> shown(List<Event> oldestFirst, {String? endsAt}) => ids(
    shownInChat(
      timelineOf(oldestFirst),
      endsAtEventId: endsAt == null ? null : '\$$endsAt',
    ),
  );

  test('a poll without votes stays where it was started', () {
    expect(shown([text('a'), poll('p'), text('b')]), ['b', 'p', 'a']);
  });

  test('a vote moves the poll to the bottom', () {
    expect(shown([poll('p'), text('a'), text('b'), vote('v', 'p')]), [
      'p',
      'b',
      'a',
    ]);
  });

  test('messages written after the vote come below the poll', () {
    expect(
      shown([poll('p'), text('a'), vote('v', 'p'), text('b'), text('c')]),
      ['c', 'b', 'p', 'a'],
    );
  });

  test('the newest of several votes counts', () {
    expect(
      shown([
        poll('p'),
        text('a'),
        vote('v1', 'p'),
        text('b'),
        vote('v2', 'p', sender: '@carol:test'),
        text('c'),
      ]),
      ['c', 'p', 'b', 'a'],
    );
  });

  test('two polls each go to their own newest vote', () {
    expect(
      shown([
        poll('p1'),
        poll('p2'),
        text('a'),
        vote('v2', 'p2'),
        text('b'),
        vote('v1', 'p1'),
      ]),
      ['p1', 'b', 'p2', 'a'],
    );
  });

  test('votes after the poll has ended do not move it', () {
    expect(
      shown([
        poll('p'),
        text('a'),
        vote('v1', 'p'),
        text('b'),
        end('e', 'p'),
        text('c'),
        vote('v2', 'p'),
      ]).where((id) => id != 'e').toList(),
      ['c', 'b', 'p', 'a'],
    );
  });

  test('a deleted vote does not move the poll', () {
    final deleted = vote('v', 'p')
      ..setRedactionEvent(
        event('r', EventTypes.Redaction, {}, sender: '@bob:test'),
      );
    expect(shown([poll('p'), text('a'), deleted]), ['a', 'p']);
  });

  test('a vote that failed to send does not move the poll', () {
    expect(
      shown([
        poll('p'),
        text('a'),
        vote('v', 'p', sender: '@alice:test', status: EventStatus.error),
      ]),
      ['a', 'p'],
    );
  });

  test('an end from someone not allowed to end it does not count', () {
    expect(
      shown([
        poll('p'),
        text('a'),
        end('e', 'p', sender: '@mallory:test'),
        text('b'),
        vote('v', 'p'),
      ]).where((id) => id != 'e').toList(),
      ['p', 'b', 'a'],
    );
  });

  test('while newer messages are held back, the poll stays in sight', () {
    // Bob reads further up; the list ends at 'a'. A vote comes in below.
    final events = [poll('p'), text('a'), text('b'), vote('v', 'p')];
    expect(shown(events, endsAt: 'a'), ['a', 'p']);
    // Back at the bottom, the poll is there
    expect(shown(events), ['p', 'b', 'a']);
  });

  test('a poll that moved down stays there while messages are held back', () {
    // Bob votes, then Alice reads further up from 'a'; Carol writes 'b'
    final events = [poll('p'), text('x'), text('a'), vote('v', 'p'), text('b')];
    expect(shown(events, endsAt: 'a'), ['p', 'a', 'x']);
  });

  test('a moved poll counts as the day of its vote for the dates', () {
    final p = poll('p');
    final v = vote('v', 'p');
    final moved = <String, Event>{};
    final list = shownInChat(timelineOf([p, text('a'), v]), moved: moved);
    expect(ids(list), ['p', 'a']);
    expect(shownTime(list.first, moved), v.originServerTs);
    expect(shownTime(list.last, moved), list.last.originServerTs);
  });

  test('a read marker on a moved poll shows where the poll was', () {
    final events = [text('a'), poll('p'), text('b'), vote('v', 'p')];
    final timeline = timelineOf(events);
    final moved = <String, Event>{};
    final list = shownInChat(timeline, moved: moved);
    expect(ids(list), ['p', 'b', 'a']);
    // Read up to the poll: 'a' and older are read, 'b' is not
    expect(readMarkerShownAt(list, timeline, moved, '\$p'), '\$a');
    expect(readMarkerShownAt(list, timeline, moved, '\$b'), '\$b');
  });
}
