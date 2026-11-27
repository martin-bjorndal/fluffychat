// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/gruppechat/group_mentions.dart';
import 'package:fluffychat/gruppechat/group_state.dart';
import 'package:fluffychat/pages/chat/events/html_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/test_client.dart';

void main() {
  const linkColor = Color(0xFF2266CC);
  late Client client;
  late Room room;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    client = await prepareTestClient();
    // A group chat outside a space is its own group
    room = Room(id: '!chat:example.invalid', client: client);
    room.setState(
      StrippedStateEvent(
        type: GruppechatEventTypes.role,
        content: const {'name': 'Spillkveld'},
        senderId: '@admin:example.invalid',
        stateKey: 'spillkveld',
      ),
    );
    client.rooms.add(room);
  });

  List<String> marked(String text) => [
    for (final (start, end) in gruppechatMentionRanges(room, text))
      text.substring(start, end),
  ];

  test('finds the group\'s roles and @alle', () {
    expect(marked('@spillkveld og @Spillkveld, @alle!'), [
      '@spillkveld',
      '@Spillkveld',
      '@alle',
    ]);
    expect(marked('@kor'), isEmpty);
  });

  test('leaves web and e-mail addresses whole', () {
    expect(marked('sjå https://example.org/@alle og x@alle.no'), isEmpty);
    expect(marked('https://example.org/x @alle'), ['@alle']);
  });

  test('a direct chat marks nothing', () {
    client.accountData['m.direct'] = BasicEvent(
      type: 'm.direct',
      content: {
        '@bob:example.invalid': [room.id],
      },
    );
    expect(marked('@alle @spillkveld'), isEmpty);
  });

  test('a direct chat in a group\'s space marks its roles, not @alle', () {
    final space = Room(id: '!space:example.invalid', client: client);
    for (final (type, key, content) in [
      (EventTypes.RoomCreate, '', {'type': RoomCreationTypes.mSpace}),
      (
        EventTypes.SpaceChild,
        room.id,
        {
          'via': ['example.invalid'],
        },
      ),
      (GruppechatEventTypes.role, 'kor', {'name': 'Kor'}),
    ]) {
      space.setState(
        StrippedStateEvent(
          type: type,
          content: content,
          senderId: '@admin:example.invalid',
          stateKey: key,
        ),
      );
    }
    client.rooms.add(space);
    client.accountData['m.direct'] = BasicEvent(
      type: 'm.direct',
      content: {
        '@bob:example.invalid': [room.id],
      },
    );
    // As mentionsOwnGroupRole and mentionsAllInChat decide
    expect(marked('@alle @kor'), ['@kor']);
  });

  testWidgets('a message shows the tags like a @username', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HtmlMessage(
            html: 'Hei @spillkveld og <b>@alle</b>, sjå https://example.org',
            room: room,
            fontSize: 14,
            linkStyle: const TextStyle(color: linkColor),
            onOpen: (_) {},
          ),
        ),
      ),
    );
    final spans = <TextSpan>[];
    for (final text in tester.widgetList<RichText>(find.byType(RichText))) {
      text.text.visitChildren((span) {
        if (span is TextSpan && span.text != null) spans.add(span);
        return true;
      });
    }
    TextSpan spanOf(String text) => spans.firstWhere((s) => s.text == text);
    for (final tag in ['@spillkveld', '@alle']) {
      final style = spanOf(tag).style!;
      expect(style.color, linkColor, reason: tag);
      expect(style.decoration, TextDecoration.underline, reason: tag);
    }
    expect(spanOf('Hei ').style?.decoration, isNull);
    expect(spans.map((s) => s.text), contains('https://example.org'));
  });
}
