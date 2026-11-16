// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Reports reach the server's admins: someone reports a person or a message,
// as the app does from a profile (widgets/member_actions_popup_menu_button
// .dart) or a message's menu (pages/chat/chat.dart), and the server posts it
// in a private room «Rapporter» for its admins
// (deploy/synapse-modules/gruppechat_reports.py). An admin who replies to a
// report there, or answers in its thread, has the answer passed on to
// whoever sent the report, in a read-only chat «Svar på rapporter».

@Timeout(Duration(minutes: 3))
library;

import 'package:collection/collection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'utils/test_server.dart';

void main() {
  group('Reports', skip: skipWithoutTestServer, () {
    late Client alice;
    late Client bob;
    late Client carol;
    late Timeline reports;

    setUpAll(() async {
      alice = await logIn('alice');
      bob = await logIn('bob');
      carol = await logIn('carol');
    });
    tearDownAll(logOutEveryone);

    Room? reportsRoom(Client client) => client.rooms.firstWhereOrNull(
      (room) => room.getLocalizedDisplayname() == 'Rapporter',
    );

    test('a reported person reaches the admins', () async {
      await bob.reportUser(carol.userID!, 'Sender meg stygge meldinger');

      // alice is the server's admin; she is invited to the room
      final invite = await valueOf(
        'alice is invited to the reports room',
        () => reportsRoom(alice),
        timeout: const Duration(seconds: 60),
      );
      final room = await accept(alice, invite.id);
      reports = await room.getTimeline();
      final report = await inHistory(
        reports,
        'the report about carol',
        (e) => textOf(e).contains(carol.userID!),
      );
      final text = textOf(report);
      expect(text, contains('Rapport om en bruker'));
      expect(text, contains(bob.userID));
      expect(text, contains('Sender meg stygge meldinger'));
    });

    test('a reported message reaches the admins, with a link to it', () async {
      final (carolChat, bobChat) = await directChat(carol, bob);
      final eventId = (await carolChat.sendTextEvent('Noe stygt'))!;
      final bobTimeline = await bobChat.getTimeline();
      await arrives(
        bobTimeline,
        'carol\'s message',
        (e) => e.eventId == eventId,
      );

      await bob.reportEvent(bobChat.id, eventId, reason: 'Stygg melding');

      final report = await arrives(
        reports,
        'the report about the message',
        (e) => textOf(e).contains(eventId),
        timeout: const Duration(seconds: 60),
      );
      final text = textOf(report);
      expect(text, contains('Rapport om en melding'));
      expect(text, contains(carol.userID));
      expect(text, contains('Stygg melding'));
      expect(text, contains('https://matrix.to/#/${bobChat.id}/$eventId'));
    });

    test('people who are not admins never see the reports', () async {
      expect(reportsRoom(bob), isNull);
      expect(reportsRoom(carol), isNull);
    });

    Room? answersRoom(Client client) => client.rooms.firstWhereOrNull(
      (room) => room.getLocalizedDisplayname() == 'Svar på rapporter',
    );

    test('an admin\'s reply to a report reaches whoever sent it', () async {
      final report = await inHistory(
        reports,
        'the report about carol',
        (e) =>
            e.senderId != alice.userID &&
            textOf(e).contains('Rapport om en bruker'),
      );

      // As the app does when alice swipes the report to reply
      final answerId = (await reports.room.sendTextEvent(
        'Takk, vi har snakket med henne.',
        inReplyTo: report,
      ))!;

      final invite = await valueOf(
        'bob is invited to the chat with answers',
        () => answersRoom(bob),
      );
      final room = await accept(bob, invite.id);
      final answer = await inHistory(
        await room.getTimeline(),
        'the answer',
        (e) => textOf(e).contains('Takk, vi har snakket med henne.'),
      );
      final text = textOf(answer);
      expect(text, contains('Svar på rapporten din om en bruker'));
      expect(text, contains('Sender meg stygge meldinger'));
      // Not the quote of the report that a reply starts with
      expect(text, isNot(contains('Rapport om en bruker')));
      expect(text, isNot(contains(alice.userID)));
      // bob only reads here
      expect(room.canSendDefaultMessages, isFalse);

      // alice sees that it went
      await arrives(
        reports,
        'the ✅ on the answer',
        (e) =>
            e.type == EventTypes.Reaction &&
            e.relationshipEventId == answerId &&
            e.content.tryGetMap<String, Object?>('m.relates_to')?['key'] ==
                '✅',
      );
      expect(answersRoom(carol), isNull);
    });

    test('an answer in a report\'s thread goes to the same chat', () async {
      final report = await inHistory(
        reports,
        'the report about the message',
        (e) =>
            e.senderId != alice.userID &&
            textOf(e).contains('Rapport om en melding'),
      );

      await reports.room.sendTextEvent(
        'Meldingen er fjernet.',
        threadRootEventId: report.eventId,
      );

      final room = answersRoom(bob)!;
      final timeline = await room.getTimeline();
      final answer = await arrives(
        timeline,
        'the answer from the thread',
        (e) => textOf(e).contains('Meldingen er fjernet.'),
      );
      expect(textOf(answer), contains('Svar på rapporten din om en melding'));
      expect(textOf(answer), contains('Stygg melding'));
      expect(
        bob.rooms.where(
          (r) => r.getLocalizedDisplayname() == 'Svar på rapporter',
        ),
        hasLength(1),
      );
    });

    test('other messages in the reports room go nowhere', () async {
      await reports.room.sendTextEvent('Hei, er det noen her?');
      final report = await inHistory(
        reports,
        'the report about carol',
        (e) =>
            e.senderId != alice.userID &&
            textOf(e).contains('Rapport om en bruker'),
      );
      // A reply to the answer the room's account reacted to, not a report
      final answer = reports.events.firstWhere(
        (e) => textOf(e).contains('Takk, vi har snakket med henne.'),
      );
      await reports.room.sendTextEvent('Bra svar', inReplyTo: answer);
      // And one to the report again, which does go, so we know when to look
      await reports.room.sendTextEvent('Siste svar.', inReplyTo: report);

      final timeline = await answersRoom(bob)!.getTimeline();
      await arrives(
        timeline,
        'the last answer',
        (e) => textOf(e).contains('Siste svar.'),
      );
      expect(
        timeline.events.where(
          (e) =>
              textOf(e).contains('Hei, er det noen her?') ||
              textOf(e).contains('Bra svar'),
        ),
        isEmpty,
      );
    });
  });
}
