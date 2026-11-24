// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/gruppechat/avatar_letters.dart';
import 'package:fluffychat/gruppechat/avatar_ring.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../utils/test_client.dart';

void main() {
  test('avatarFallbackLetters takes whole characters, emojis too', () {
    expect(avatarFallbackLetters(null), '@');
    expect(avatarFallbackLetters('  '), '@');
    expect(avatarFallbackLetters('Alice'), 'A');
    expect(avatarFallbackLetters(' Tor Helge '), 'TH');
    expect(avatarFallbackLetters('Alice Bob Carol'), 'AC');
    expect(avatarFallbackLetters('🎉 fest'), '🎉f');
    expect(avatarFallbackLetters('💔'), '💔');
    expect(avatarFallbackLetters('Venner 💔'), 'V💔');
    expect(avatarFallbackLetters('👨‍👩‍👧 Familien'), '👨‍👩‍👧F');
    // More than one space between words
    expect(avatarFallbackLetters('Tor  Helge'), 'TH');
  });

  late Client client;
  setUpAll(() async => client = await prepareTestClient());

  // Reported in 1.1.17: a chat named with an emoji first crashed the screen
  // with "string is not well-formed UTF-16"
  for (final name in ['💔', '💔 Venner', 'Venner 💔', 'Tor  Helge']) {
    testWidgets('an avatar for "$name" shows without errors', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Avatar(name: name, client: client),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text(avatarFallbackLetters(name)), findsWidgets);
    });
  }

  testWidgets("a ring keeps the avatar's size, and only shows with a colour", (
    tester,
  ) async {
    for (final color in [null, const Color(0xFFE91E63)]) {
      for (final size in [16.0, Avatar.defaultSize, 120.0]) {
        await tester.pumpWidget(
          Center(
            child: gruppechatRingedAvatar(
              size,
              color,
              SizedBox.square(dimension: size, child: const Placeholder()),
            ),
          ),
        );
        expect(
          tester.getRect(find.byType(Placeholder).first).width,
          color == null ? size : lessThan(size),
        );
        expect(
          find.byKey(avatarRingKey),
          color == null ? findsNothing : findsOneWidget,
        );
        final outer = tester.getSize(find.byType(Container).first);
        expect(outer, Size.square(size));
      }
    }
  });
}
