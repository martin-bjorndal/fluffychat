// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Each person's read position, shown under the message they read up to
// (lib/gruppechat/read_positions.dart), worked out from the read receipts
// the server sends, the way the chat page reads them.

@Timeout(Duration(minutes: 3))
library;

import 'package:fluffychat/gruppechat/read_positions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'utils/test_server.dart';

void main() {
  group('Read positions', skip: skipWithoutTestServer, () {
    late Client alice;
    late Client bob;
    late Client carol;
    late Timeline aliceTimeline;
    late Timeline bobTimeline;
    late Timeline carolTimeline;
    late List<String> messages;

    Map<String, List<String>> positions() =>
        gruppechatReadPositions(timeline: aliceTimeline);

    Future<void> showsReaders(Map<String, List<String>> expected) => eventually(
      'alice sees the read positions $expected',
      () => positions().toString() == expected.toString(),
    );

    setUpAll(() async {
      alice = await logIn('alice');
      bob = await logIn('bob');
      carol = await logIn('carol');
      final group = await newGroup(alice, [bob, carol]);
      aliceTimeline = await alice
          .getRoomById(group.firstChannel)!
          .getTimeline();
      bobTimeline = await bob.getRoomById(group.firstChannel)!.getTimeline();
      carolTimeline = await carol
          .getRoomById(group.firstChannel)!
          .getTimeline();
      messages = [
        for (final text in ['Én', 'To', 'Tre'])
          (await aliceTimeline.room.sendTextEvent(text))!,
      ];
      for (final timeline in [bobTimeline, carolTimeline]) {
        await arrives(timeline, 'the last message', (e) => e.body == 'Tre');
      }
    });
    tearDownAll(logOutEveryone);

    test('a reader shows under the message they read up to', () async {
      // As the chat page marks what is on screen as read
      await bobTimeline.setReadMarker(eventId: messages[1], public: true);
      await showsReaders({
        messages[1]: [bob.userID!],
      });
    });

    test('someone who turned off read receipts is not shown', () async {
      await carolTimeline.setReadMarker(eventId: messages[2], public: false);
      // Give the private receipt time to arrive, if it wrongly did
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(positions().values.expand((readers) => readers), [bob.userID]);
    });

    test('writing moves you below your own message', () async {
      final eventId = await bobTimeline.room.sendTextEvent('Jeg har lest!');
      await showsReaders({
        eventId!: [bob.userID!],
      });
    });

    test('everyone who has read the newest message shares it', () async {
      final eventId = await aliceTimeline.room.sendTextEvent('Fire');
      await arrives(bobTimeline, 'the newest', (e) => e.eventId == eventId);
      await bobTimeline.setReadMarker(eventId: eventId, public: true);
      await showsReaders({
        eventId!: [bob.userID!],
      });
      // Carol now writes, but still sends no receipts
      await carolTimeline.room.sendTextEvent('Hei');
      await arrives(aliceTimeline, 'carol\'s message', (e) => e.body == 'Hei');
      expect(positions().values.expand((readers) => readers), [bob.userID]);
    });

    test('a reaction counts as reading the message it reacts to', () async {
      final eventId = await aliceTimeline.room.sendTextEvent('Reager!');
      await arrives(bobTimeline, 'the message', (e) => e.eventId == eventId);
      final reactionId = await bobTimeline.room.sendReaction(eventId!, '❤️');
      // Bob's app marks his reaction, the newest event, as read
      await arrives(
        bobTimeline,
        'his reaction',
        (e) => e.eventId == reactionId,
      );
      await bobTimeline.setReadMarker(eventId: reactionId, public: true);
      await showsReaders({
        eventId: [bob.userID!],
      });
    });

    test('someone who leaves is no longer shown', () async {
      await bobTimeline.room.leave();
      await showsReaders({});
    });
  });
}
