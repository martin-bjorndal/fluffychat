// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/gruppechat/edit_history.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
// ignore: implementation_imports
import 'package:matrix/src/models/timeline_chunk.dart';

import '../utils/test_client.dart';

void main() {
  late Client client;
  late Room room;

  setUpAll(() async {
    client = await prepareTestClient(loggedIn: true);
    room = Room(id: '!room:example.invalid', client: client);
  });

  const alice = '@alice:example.invalid';
  const bob = '@bob:example.invalid';
  const original = r'$original';

  Event message(String id, String text, int minute, {String sender = alice}) =>
      Event(
        content: {'msgtype': MessageTypes.Text, 'body': text},
        type: EventTypes.Message,
        eventId: id,
        senderId: sender,
        originServerTs: DateTime(2026, 11, 22, 18, minute),
        room: room,
      );

  Event edit(String id, String text, int minute, {String sender = alice}) =>
      Event(
        content: {
          'msgtype': MessageTypes.Text,
          'body': '* $text',
          'm.new_content': {'msgtype': MessageTypes.Text, 'body': text},
          'm.relates_to': {
            'rel_type': RelationshipTypes.edit,
            'event_id': original,
          },
        },
        type: EventTypes.Message,
        eventId: id,
        senderId: sender,
        originServerTs: DateTime(2026, 11, 22, 18, minute),
        room: room,
      );

  Timeline timelineOf(List<Event> events) => Timeline(
    room: room,
    chunk: TimelineChunk(events: events.reversed.toList()),
  );

  Future<void> pumpLabel(
    WidgetTester tester,
    Timeline timeline, {
    required bool enabled,
  }) => tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: GruppechatEditedLabel(
          event: timeline.events.firstWhere((e) => e.eventId == original),
          timeline: timeline,
          enabled: enabled,
          child: const Text('(redigert)'),
        ),
      ),
    ),
  );

  test('the versions are the sender\'s own edits, oldest first', () {
    final timeline = timelineOf([
      message(original, 'Møte klokka 18', 0),
      edit(r'$later', 'Møte klokka 19.30', 9),
      edit(r'$bob', 'Bob var her', 5, sender: bob),
      edit(r'$first', 'Møte klokka 19', 3),
    ]);
    final event = timeline.events.firstWhere((e) => e.eventId == original);
    expect(gruppechatWasEdited(event, timeline), isTrue);
    final versions = gruppechatEditHistory(
      event,
      timeline,
      const MatrixDefaultLocalizations(),
    );
    expect(versions.map((v) => v.text), [
      'Møte klokka 18',
      'Møte klokka 19',
      'Møte klokka 19.30',
    ]);
    expect(versions.first.time, DateTime(2026, 11, 22, 18, 0));
    // The newest version is what the chat shows
    expect(versions.last.text, event.getDisplayEvent(timeline).body);
  });

  test('a message only someone else "edited" is not edited', () {
    final timeline = timelineOf([
      message(original, 'Hei', 0),
      edit(r'$bob', 'Bob var her', 5, sender: bob),
    ]);
    final event = timeline.events.firstWhere((e) => e.eventId == original);
    expect(gruppechatWasEdited(event, timeline), isFalse);
    expect(
      gruppechatEditHistory(
        event,
        timeline,
        const MatrixDefaultLocalizations(),
      ),
      isEmpty,
    );
  });

  testWidgets('the dialog marks the original and the current version', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: GruppechatEditHistoryDialog(
          versions: [
            MessageVersion(DateTime(2026, 11, 22, 18), 'Møte klokka 18'),
            MessageVersion(DateTime(2026, 11, 22, 18, 3), 'Møte klokka 19'),
            MessageVersion(DateTime(2026, 11, 22, 18, 9), 'Møte klokka 19.30'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Earlier versions'), findsOneWidget);
    expect(find.text('Møte klokka 18'), findsOneWidget);
    expect(find.text('Møte klokka 19'), findsOneWidget);
    expect(find.text('Møte klokka 19.30'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^Original · ')), findsOneWidget);
    expect(find.textContaining(RegExp(r'^Now · ')), findsOneWidget);
    // The one in between has only its time
    expect(
      find.textContaining(RegExp(r'^Nov 22(, 2026)?, 18:03$')),
      findsOneWidget,
    );
  });

  testWidgets('tapping "(redigert)" opens the versions', (tester) async {
    final timeline = timelineOf([
      message(original, 'Møte klokka 18', 0),
      edit(r'$first', 'Møte klokka 19', 3),
    ]);
    await pumpLabel(tester, timeline, enabled: true);
    await tester.pumpAndSettle();
    await tester.tap(find.text('(redigert)'));
    await tester.pumpAndSettle();
    expect(find.text('Møte klokka 18'), findsOneWidget);
    expect(find.text('Møte klokka 19'), findsOneWidget);
  });

  testWidgets('while selecting, tapping "(redigert)" opens nothing', (
    tester,
  ) async {
    final timeline = timelineOf([
      message(original, 'Møte klokka 18', 0),
      edit(r'$first', 'Møte klokka 19', 3),
    ]);
    await pumpLabel(tester, timeline, enabled: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('(redigert)'));
    await tester.pumpAndSettle();
    expect(find.byType(GruppechatEditHistoryDialog), findsNothing);
  });
}
