// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Reports reach the server's admins: someone reports a person or a message,
// as the app does from a profile (widgets/member_actions_popup_menu_button
// .dart) or a message's menu (pages/chat/chat.dart), and the server posts it
// in a private room «Rapporter» for its admins
// (deploy/synapse-modules/gruppechat_reports.py).

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
  });
}
