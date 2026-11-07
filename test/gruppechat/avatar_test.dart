// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/gruppechat/avatar_letters.dart';
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
}
