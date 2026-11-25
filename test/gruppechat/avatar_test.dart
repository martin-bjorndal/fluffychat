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

  const pink = Color(0xFFE91E63);
  const looks = <AvatarRingLook?>[
    null,
    AvatarRingLook(pink),
    AvatarRingLook(pink, AvatarRingKind.glitter),
    AvatarRingLook.christmas,
  ];

  AvatarRingLook? ringIn(WidgetTester tester) {
    final painter = tester
        .widget<CustomPaint>(find.byKey(avatarRingKey))
        .foregroundPainter;
    return painter is AvatarRingPainter ? painter.look : null;
  }

  testWidgets("a ring keeps the avatar's size, and only shows with a look", (
    tester,
  ) async {
    for (final look in looks) {
      for (final size in [16.0, Avatar.defaultSize, 120.0]) {
        await tester.pumpWidget(
          Center(
            child: gruppechatRingedAvatar(
              size,
              look,
              SizedBox.square(dimension: size, child: const Placeholder()),
            ),
          ),
        );
        expect(tester.takeException(), isNull, reason: '$look at $size');
        expect(
          tester.getRect(find.byType(Placeholder).first).width,
          look == null ? size : lessThan(size),
        );
        expect(ringIn(tester), look);
        expect(tester.getSize(find.byKey(avatarRingKey)), Size.square(size));
      }
    }
  });

  testWidgets('the picture stays when the ring comes, changes and goes', (
    tester,
  ) async {
    // Not a GlobalKey: that would keep the element whatever the tree
    const picture = ValueKey('picture');
    Element? first;
    for (final look in [...looks, null]) {
      await tester.pumpWidget(
        Center(
          child: gruppechatRingedAvatar(
            Avatar.defaultSize,
            look,
            SizedBox.square(key: picture, dimension: Avatar.defaultSize),
          ),
        ),
      );
      expect(ringIn(tester), look);
      // The same element, so a picture in it isn't loaded again
      final element = tester.element(find.byKey(picture));
      expect(identical(element, first ??= element), isTrue, reason: '$look');
    }
  });

  test('the kind of ring comes from its own profile field', () {
    AvatarRingKind kind(Object? value) =>
        avatarRingKindFromProfile({avatarRingStyleField: ?value});
    expect(kind('glitter'), AvatarRingKind.glitter);
    expect(kind('christmas'), AvatarRingKind.christmas);
    expect(kind(null), AvatarRingKind.plain);
    expect(kind('plain'), AvatarRingKind.plain);
    expect(kind('rainbow'), AvatarRingKind.plain);
    expect(kind(1), AvatarRingKind.plain);
    expect(
      const AvatarRingLook(pink, AvatarRingKind.glitter),
      AvatarRingLook(Color(pink.toARGB32()), AvatarRingKind.glitter),
    );
    expect(
      const AvatarRingLook(pink),
      isNot(const AvatarRingLook(pink, AvatarRingKind.glitter)),
    );
    // What a 1.1.45 app shows for a Christmas ring is a colour it offers
    expect(
      avatarRingFromProfile({
        avatarRingField: AvatarRingLook.christmas.color.toARGB32(),
      }),
      AvatarRingLook.christmas.color,
    );
  });

  test('the ring dialog picks and marks rings as shown', () {
    final pinkArgb = pink.toARGB32();
    expect(
      avatarRingFromSwatch(pinkArgb, glitter: false),
      const AvatarRingLook(pink),
    );
    expect(
      avatarRingFromSwatch(pinkArgb, glitter: true),
      const AvatarRingLook(pink, AvatarRingKind.glitter),
    );
    expect(avatarRingSwatchIsCurrent(null, pinkArgb), isFalse);
    expect(
      avatarRingSwatchIsCurrent(const AvatarRingLook(pink), pinkArgb),
      isTrue,
    );
    expect(
      avatarRingSwatchIsCurrent(
        const AvatarRingLook(pink, AvatarRingKind.glitter),
        pinkArgb,
      ),
      isTrue,
    );
    final christmasRed = AvatarRingLook.christmas.color.toARGB32();
    expect(
      avatarRingSwatchIsCurrent(AvatarRingLook.christmas, christmasRed),
      isFalse,
      reason: 'the Christmas tile is marked, not the red swatch',
    );
  });
}
