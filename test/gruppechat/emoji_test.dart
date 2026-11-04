// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/gruppechat/emoji.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
