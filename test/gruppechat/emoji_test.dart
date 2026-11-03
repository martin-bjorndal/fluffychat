// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/gruppechat/emoji.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('one emoji counts, with skin tones, flags and joined emojis', () {
    for (final emoji in ['😂', '❤️', '👍🏽', '🇳🇴', '👨‍👩‍👧', ' 🎉 ']) {
      expect(isSingleEmoji(emoji), isTrue, reason: emoji);
    }
  });

  test('text, several emojis and nothing do not', () {
    for (final text in ['hei', 'ok 👍', '😂😂', '1', '', ' ']) {
      expect(isSingleEmoji(text), isFalse, reason: text);
    }
  });
}
