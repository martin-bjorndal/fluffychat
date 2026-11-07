// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/widgets.dart' show StringCharacters;

/// The letters of an avatar without a picture: the first character of the
/// first and last word of [name], or '@' without a name.
///
/// Whole characters, so an emoji isn't cut in half. Before 1.1.18 the Avatar
/// widget took the first UTF-16 code unit, and a chat named "💔" crashed the
/// screen with "string is not well-formed UTF-16".
String avatarFallbackLetters(String? name) {
  final words = (name ?? '')
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) return '@';
  if (words.length == 1) return words.single.characters.first;
  return '${words.first.characters.first}${words.last.characters.first}';
}
