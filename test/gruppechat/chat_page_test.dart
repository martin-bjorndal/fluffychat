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
}
