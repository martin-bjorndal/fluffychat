// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Wish from 1.1.43 (Synnøve, Martin): a chat's colour coloured your own
// bubbles and the bars, but other people's bubbles stayed grey whatever
// colour the chat had. Now they take a tint of it. How it looks can only be
// seen on a phone.

@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/gruppechat/chat_colors.dart';
import 'package:fluffychat/gruppechat/matrix_group.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/test_server.dart';

void main() {
  group(
    'Chat colour on other people\'s bubbles',
    skip: skipWithoutTestServer,
    () {
      const pink = 0xFFE91E63;
      late Room aliceChat;
      late Room bobChat;

      setUpAll(() async {
        // Widget tests block the network; these talk to the test server
        HttpOverrides.global = null;
        final alice = await logIn('alice');
        final bob = await logIn('bob');
        (aliceChat, bobChat) = await directChat(alice, bob);
      });
      tearDownAll(logOutEveryone);

      for (final brightness in Brightness.values) {
        testWidgets('bob colours the chat pink, and alice sees his bubbles '
            'pinkish in $brightness', (tester) async {
          SharedPreferences.setMockInitialValues({});
          await AppSettings.init(loadWebConfigFile: false);
          // The chat page's theme, as alice has it open
          ThemeData? seen;
          Future<void> openChat() => tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: GruppechatChatColorTheme(
                room: aliceChat,
                child: Builder(
                  builder: (context) {
                    seen = Theme.of(context);
                    return const SizedBox();
                  },
                ),
              ),
            ),
          );

          await openChat();
          final grey = seen!.colorScheme.surfaceContainerHigh;
          expect(gruppechatOthersBubbleColor(seen!), grey);

          await tester.runAsync(() async {
            await bobChat.gruppechatBackgroundGroup!.setChatColor(
              bobChat,
              pink,
            );
            await eventually(
              'alice sees the colour',
              () => aliceChat.gruppechatChatColor == pink,
            );
          });
          await openChat();
          final tinted = gruppechatOthersBubbleColor(seen!);
          expect(tinted, isNot(grey));
          // Pink shows in it: more red than green or blue
          expect(tinted.r, greaterThan(tinted.g));
          expect(tinted.r, greaterThan(tinted.b));
          // Their text still reads on it
          final contrast =
              (tinted.computeLuminance() -
                      seen!.colorScheme.onSurface.computeLuminance())
                  .abs();
          expect(contrast, greaterThan(0.3));

          // Back to the app's own colours, and grey bubbles again
          await tester.runAsync(() async {
            await aliceChat.gruppechatBackgroundGroup!.setChatColor(
              aliceChat,
              null,
            );
            await eventually(
              'alice sees it removed',
              () => aliceChat.gruppechatChatColor == null,
            );
          });
          await openChat();
          expect(gruppechatOthersBubbleColor(seen!), grey);
        });
      }
    },
  );
}
