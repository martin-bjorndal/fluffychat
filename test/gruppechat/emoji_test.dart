// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui' show Locale;

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart' as picker;
import 'package:fluffychat/gruppechat/emoji.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('The emoji keyboard', () {
    const locales = [Locale('nb'), Locale('en'), Locale('de'), Locale('fr')];

    List<String> emojis(Locale locale, picker.Category category) =>
        gruppechatEmojiSet(locale)
            .firstWhere((c) => c.category == category)
            .emoji
            .map((emoji) => emoji.emoji)
            .toList();

    test('has 🥲, next to the other smiling faces', () {
      for (final locale in locales) {
        final smileys = emojis(locale, picker.Category.SMILEYS);
        expect(smileys, contains('🥲'), reason: '$locale');
        expect(
          smileys.indexOf('🥲'),
          smileys.indexOf('😙') + 1,
          reason: '$locale',
        );
      }
    });

    test('has the newer hearts and faces too', () {
      for (final locale in locales) {
        final all = gruppechatEmojiSet(
          locale,
        ).expand((c) => c.emoji.map((emoji) => emoji.emoji));
        for (final emoji in ['🥱', '🥸', '😮‍💨', '🤍', '🤎', '🩷', '🫶']) {
          expect(all, contains(emoji), reason: '$emoji in $locale');
        }
      }
    });

    test('puts each added emoji right after the one it belongs with', () {
      for (final locale in locales) {
        final set = gruppechatEmojiSet(locale);
        for (final (emoji, after) in addedKeyboardEmojis) {
          final category = set.firstWhere(
            (c) => c.emoji.any((e) => e.emoji == emoji.emoji),
            orElse: () => throw TestFailure('${emoji.emoji} in $locale'),
          );
          final emojis = category.emoji.map((e) => e.emoji).toList();
          expect(
            emojis.indexOf(emoji.emoji),
            emojis.indexOf(after) + 1,
            reason: '${emoji.emoji} after $after in $locale',
          );
        }
      }
    });

    test('has each emoji once in a category', () {
      for (final locale in locales) {
        for (final category in gruppechatEmojiSet(locale)) {
          final emojis = category.emoji.map((emoji) => emoji.emoji).toList();
          expect(
            emojis.toSet().length,
            emojis.length,
            reason: '${category.category} in $locale',
          );
        }
      }
    });
  });

  test('emojis count as people see them, with spaces anywhere', () {
    const counts = {
      '😂': 1,
      '❤️': 1,
      '👍🏽': 1,
      '🇳🇴': 1,
      '👨‍👩‍👧': 1,
      ' 🎉 ': 1,
      '😂😂': 2,
      '🇳🇴👍🏽 ❤️ ': 3,
    };
    for (final MapEntry(key: text, value: count) in counts.entries) {
      expect(emojiCount(text), count, reason: text);
    }
  });

  test('text, or nothing, is not emojis', () {
    for (final text in ['hei', 'ok 👍', '1', '', ' ']) {
      expect(emojiCount(text), isNull, reason: text);
    }
  });

  test('the more emojis, the smaller, down to six', () {
    expect(bigEmojiScale(1), greaterThan(bigEmojiScale(2)));
    expect(bigEmojiScale(3), greaterThan(bigEmojiScale(6)));
    expect(bigEmojiScale(6), greaterThan(1));
  });
}
