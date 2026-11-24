// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// The files the sounds and effects need (lib/gruppechat/sounds.dart,
// effects.dart, made by scripts/gruppechat_sounds.py), and an effect's
// animation, which goes once it has played. How it looks and sounds can
// only be checked on a phone.

import 'dart:io';

import 'package:fluffychat/gruppechat/effects.dart';
import 'package:fluffychat/gruppechat/sounds.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('every sound is in the app, and Android has the notification ones', () {
    for (final sound in GruppechatSound.values) {
      expect(File(sound.asset).existsSync(), isTrue, reason: sound.asset);
      final raw = 'android/app/src/main/res/raw/${sound.file}.wav';
      expect(File(raw).existsSync(), isTrue, reason: raw);
      // Android's resource names allow only these
      expect(sound.file, matches(RegExp(r'^[a-z0-9_]+$')));
    }
    for (final effect in GruppechatEffect.values) {
      expect(File(effect.asset).existsSync(), isTrue, reason: effect.asset);
    }
    expect(File('assets/sounds/gc_received.wav').existsSync(), isTrue);
  });

  testWidgets('an effect plays over the chat, then goes', (tester) async {
    // Each effect, and an emoji floating up on its own (lib/gruppechat/
    // effects.dart, gruppechatFloatingEmojiOf)
    for (final play in [
      for (final effect in GruppechatEffect.values)
        (effect: effect, emoji: effect.emoji),
      (effect: null, emoji: '🥰'),
    ]) {
      var done = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            children: [
              const Placeholder(),
              Positioned.fill(
                child: GruppechatEffectOverlay(
                  key: ValueKey(play),
                  play: play,
                  onDone: () => done = true,
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(CustomPaint), findsWidgets);
      expect(done, isFalse);
      await tester.pump(const Duration(seconds: 3));
      expect(done, isTrue, reason: play.emoji);
    }
  });

  // With gold glitter and snow (1.1.45) the list grew past the height a
  // bottom sheet gets on a small phone
  testWidgets('every effect can be picked on a small phone', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    GruppechatEffect? picked;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('nb'),
        localizationsDelegates: const [
          ...L10n.localizationsDelegates,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => picked = await gruppechatPickEffect(context),
            child: const Text('send'),
          ),
        ),
      ),
    );
    // The translations load first
    await tester.pumpAndSettle();
    await tester.tap(find.text('send'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final last = find.byKey(Key('effect_${GruppechatEffect.values.last.name}'));
    await tester.scrollUntilVisible(
      last,
      100,
      scrollable: find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(last);
    await tester.pumpAndSettle();
    expect(picked, GruppechatEffect.values.last);
  });
}
