// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:matrix/matrix.dart';

final _pictographic = RegExp(
  // The lint checks the pattern without the unicode flag, which \p{} needs
  // ignore: valid_regexps
  r'\p{Extended_Pictographic}|\p{Regional_Indicator}',
  unicode: true,
);

/// Most emojis a message can hold and still show big.
const maxBigEmojis = 6;

/// How many emojis [text] holds, as people see them, so skin tones, flags
/// and joined emojis such as 👨‍👩‍👧 count as one; null when it holds anything
/// but emojis and spaces.
int? emojiCount(String text) {
  final emojis = text.characters.where((c) => c.trim().isNotEmpty);
  if (emojis.isEmpty || !emojis.every(_pictographic.hasMatch)) return null;
  return emojis.length;
}

/// How much bigger than text [count] emojis alone are shown: smaller the
/// more there are, as in Messenger.
double bigEmojiScale(int count) => switch (count) {
  1 => 5,
  <= 3 => 3.5,
  _ => 2.5,
};

extension GruppechatEmojiEvent on Event {
  /// How many emojis this is, when it is a text message of only a few
  /// emojis, which the chat shows big and without a bubble.
  int? get bigEmojiCount {
    if (type != EventTypes.Message ||
        messageType != MessageTypes.Text ||
        redacted) {
      return null;
    }
    // "🎉 " is sent with the formatted text "🎉", as Markdown drops the space
    if (isRichMessage && formattedText.trim() != body.trim()) return null;
    final count = emojiCount(body);
    return count != null && count <= maxBigEmojis ? count : null;
  }
}
