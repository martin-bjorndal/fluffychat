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

/// Whether [text] is one emoji: one character as people see it, so skin
/// tones, flags and joined emojis such as 👨‍👩‍👧 count as one.
bool isSingleEmoji(String text) {
  final trimmed = text.trim();
  return trimmed.characters.length == 1 && _pictographic.hasMatch(trimmed);
}

extension GruppechatEmojiEvent on Event {
  /// Whether this is a text message of only one emoji, which the chat shows
  /// big and without a bubble, as in Messenger.
  bool get isSingleEmojiMessage =>
      type == EventTypes.Message &&
      messageType == MessageTypes.Text &&
      !redacted &&
      !isRichMessage &&
      isSingleEmoji(body);
}
