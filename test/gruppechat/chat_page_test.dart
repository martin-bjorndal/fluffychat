// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Opening a chat: the chat page starts without an error. In 1.1.24 it read
// the room before it knew which account sends (pages/chat/chat.dart), so
// every chat opened as an empty, single-coloured screen.

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/chat_view.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/test_client.dart';

void main() {
  late Client client;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    client = await prepareTestClient(loggedIn: true);
  });

  testWidgets('a chat opens without an error', (tester) async {
    final room = client.rooms.first;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Matrix(
          clients: [client],
          store: AppSettings.store,
          child: ChatPageWithRoom(room: room),
        ),
      ),
    );
    // The texts load first
    for (
      var i = 0;
      i < 20 && find.byType(ChatPageWithRoom).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // And while its messages load
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    }
    expect(find.byType(ChatView), findsOneWidget);
  });

  // lib/gruppechat/swipe_back.dart: swiping right goes back to the list
  testWidgets('swiping right on the top bar goes back to the chat list', (
    tester,
  ) async {
    // A chat the user is in: an invite opens with a "joining" dialog on top
    final room = client.rooms.firstWhere(
      (room) => room.membership == Membership.join,
    );
    // A phone: on a wide screen the list is beside the chat, and the swipe off
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        // Above the navigator, as in the app, so pushed pages find it
        builder: (context, child) =>
            Matrix(clients: [client], store: AppSettings.store, child: child),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ChatPageWithRoom(room: room),
                ),
              ),
              child: const Text('Chats'),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 30 && find.text('Chats').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Chats'));
    for (var i = 0; i < 30 && find.byType(ChatView).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(ChatView), findsOneWidget);
    final bar = tester.getCenter(find.byType(AppBar));
    await tester.dragFrom(Offset(100, bar.dy), const Offset(300, 0));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(ChatView), findsNothing);
    expect(find.text('Chats'), findsOneWidget);
    // The closed chat's timers run out
    await tester.pump(const Duration(minutes: 1));
  });
}
