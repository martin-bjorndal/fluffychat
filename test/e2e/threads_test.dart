// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Threads in a channel and the list of a chat's threads
// (lib/gruppechat/threads.dart), which the server builds and the app
// decrypts.

@Timeout(Duration(minutes: 3))
library;

import 'package:fluffychat/gruppechat/threads.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'utils/test_server.dart';

void main() {
  group('Threads', skip: skipWithoutTestServer, () {
    late Client alice;
    late Client bob;
    late Client carol;
    late TestGroup group;
    late String rootId;
    late String replyId;
    Room channel(Client client) => client.getRoomById(group.firstChannel)!;

    setUpAll(() async {
      alice = await logIn('alice');
      bob = await logIn('bob');
      carol = await logIn('carol');
      group = await newGroup(alice, [bob, carol]);
    });
    tearDownAll(logOutEveryone);

    test('a reply in a thread stays out of the main chat', () async {
      rootId = (await channel(alice).sendTextEvent('Hvem tar med kake?'))!;
      final bobTimeline = await channel(bob).getTimeline();
      await arrives(bobTimeline, 'the question', (e) => e.eventId == rootId);
      replyId = (await channel(bob).sendTextEvent(
        'Jeg baker!',
        threadRootEventId: rootId,
        threadLastEventId: rootId,
      ))!;
      final aliceTimeline = await channel(alice).getTimeline();
      final reply = await arrives(
        aliceTimeline,
        'the reply',
        (e) => e.eventId == replyId,
      );
      expect(reply.relationshipType, RelationshipTypes.thread);
      expect(reply.relationshipEventId, rootId);
      expect(reply.body, 'Jeg baker!');
    });

    test('the thread list shows each thread with its latest reply', () async {
      final thread = await fetchedValue('the thread with its reply', () async {
        final threads = (await channel(carol).loadGruppechatThreads()).threads;
        return threads.singleOrNull?.latestReply == null
            ? null
            : threads.single;
      });
      expect(thread.root.eventId, rootId);
      expect(thread.root.body, 'Hvem tar med kake?');
      expect(thread.summary.replyCount, 1);
      expect(thread.latestReply?.body, 'Jeg baker!');
    });

    test('"my threads" only has threads you took part in', () async {
      final bobs = await channel(bob).loadGruppechatThreads(onlyMine: true);
      expect(bobs.threads.map((t) => t.root.eventId), [rootId]);
      final carols = await channel(carol).loadGruppechatThreads(onlyMine: true);
      expect(carols.threads, isEmpty);
    });

    test('a deleted reply never shows as "could not decrypt"', () async {
      final secondId = await channel(bob).sendTextEvent(
        'Sjokolade eller gulrot?',
        threadRootEventId: rootId,
        threadLastEventId: replyId,
      );
      await fetchedValue('the thread list shows the second reply', () async {
        final thread = (await channel(
          carol,
        ).loadGruppechatThreads()).threads.single;
        return thread.latestReply?.eventId == secondId ? thread : null;
      });
      await channel(bob).redactEvent(secondId!);
      final thread = await fetchedValue(
        'the thread list shows the deletion',
        () async {
          final thread = (await channel(
            carol,
          ).loadGruppechatThreads()).threads.single;
          final latest = thread.latestReply;
          return latest?.eventId != secondId || latest!.redacted
              ? thread
              : null;
        },
      );
      expect(thread.summary.replyCount, greaterThanOrEqualTo(1));
      final latest = thread.latestReply!;
      expect(latest.messageType, isNot(MessageTypes.BadEncrypted));
      expect(textOf(latest), isNot(contains('decrypt')));
    });
  });
}
