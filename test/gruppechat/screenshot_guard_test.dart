// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Where a chat that blocks screenshots can't be kept out of them, as in a
// browser, its page shows only a note (lib/gruppechat/screenshot_block.dart).

import 'dart:ui' show Locale;

import 'package:fluffychat/gruppechat/screenshot_block.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../utils/test_client.dart';

void main() {
  testWidgets('the chat page shows only a note where the chat is hidden', (
    tester,
  ) async {
    final client = await tester.runAsync(
      () => prepareTestClient(loggedIn: true),
    );
    final en = (await tester.runAsync(() => lookupL10n(const Locale('en'))))!;
    var n = 0;
    Room chat({required bool blocked}) {
      final room = Room(
        id: '!guard${n++}:example.invalid',
        client: client!,
        membership: Membership.join,
      );
      if (blocked) {
        room.setState(
          Event(
            type: gruppechatScreenshotsType,
            content: {'blocked': true},
            senderId: '@bob:example.invalid',
            stateKey: '@bob:example.invalid',
            eventId: '\$block${n++}',
            originServerTs: DateTime(2026, 11, 22),
            room: room,
          ),
        );
      }
      return room;
    }

    Future<void> show(Room room) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: GruppechatScreenshotGuard(
            room: room,
            child: const Text('meldingane'),
          ),
        ),
      );
      // The texts load first
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await show(chat(blocked: false));
    expect(find.text('meldingane'), findsOneWidget);
    await show(chat(blocked: true));
    expect(find.text('meldingane'), findsNothing);
    expect(find.byKey(const Key('chat_hidden_here')), findsOneWidget);
    expect(find.text(en.gruppechatChatOnlyInApp), findsOneWidget);
  });
}
