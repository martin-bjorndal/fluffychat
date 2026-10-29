// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/gruppechat/threads.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import '../utils/test_client.dart';

void main() {
  const bob = '@bob:example.invalid';

  group('ThreadSummary.fromUnsigned', () {
    test('reads the reply count, participation and latest reply', () {
      final summary = ThreadSummary.fromUnsigned({
        'm.relations': {
          'm.thread': {
            'count': 3,
            'current_user_participated': true,
            'latest_event': {
              'type': 'm.room.message',
              'event_id': r'$reply',
              'sender': bob,
              'origin_server_ts': 1790000000000,
              'content': {'msgtype': 'm.text', 'body': 'Same here'},
            },
          },
        },
      });
      expect(summary.replyCount, 3);
      expect(summary.participated, isTrue);
      expect(summary.latestReply?.eventId, r'$reply');
      expect(summary.latestReply?.senderId, bob);
    });

    test('is empty without a thread aggregation', () {
      for (final unsigned in <Map<String, Object?>?>[
        null,
        {},
        {'m.relations': {'m.annotation': <String, Object?>{}}},
        {'m.relations': 'not a map'},
      ]) {
        final summary = ThreadSummary.fromUnsigned(unsigned);
        expect(summary.replyCount, 0);
        expect(summary.participated, isFalse);
        expect(summary.latestReply, isNull);
      }
    });

    test('ignores malformed values', () {
      final summary = ThreadSummary.fromUnsigned({
        'm.relations': {
          'm.thread': {
            'count': -2,
            'current_user_participated': 'yes',
            'latest_event': {'type': 'm.room.message'},
          },
        },
      });
      expect(summary.replyCount, 0);
      expect(summary.participated, isFalse);
      expect(summary.latestReply, isNull);
    });
  });

  group('with a room', () {
    late Room room;

    setUp(() async {
      final client = await prepareTestClient();
      room = Room(id: '!room:example.invalid', client: client);
    });

    MatrixEvent message(String eventId, int timestamp) => MatrixEvent(
      type: EventTypes.Message,
      content: {'msgtype': 'm.text', 'body': eventId},
      senderId: bob,
      eventId: eventId,
      originServerTs: DateTime.fromMillisecondsSinceEpoch(timestamp),
    );

    test('unencrypted messages are used as they are', () async {
      final event = await room.gruppechatDecrypt(message(r'$root', 1000));
      expect(event.eventId, r'$root');
      expect(event.type, EventTypes.Message);
      expect(event.room.id, room.id);
    });

    test('a thread was last active at its latest reply', () async {
      final root = await room.gruppechatDecrypt(message(r'$root', 1000));
      final reply = await room.gruppechatDecrypt(message(r'$reply', 5000));
      const summary = ThreadSummary(replyCount: 1);
      expect(
        GruppechatThread(root: root, summary: summary).lastActivity,
        root.originServerTs,
      );
      expect(
        GruppechatThread(
          root: root,
          summary: summary,
          latestReply: reply,
        ).lastActivity,
        reply.originServerTs,
      );
    });
  });
}
