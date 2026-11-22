// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Text replacements: `:)` becomes 🙂 as people type. A group's moderators can
// keep their own list, which then replaces the built-in one for everyone in
// the group. Pure Dart; `matrix_group.dart` reads and writes the list in
// rooms.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

/// State event holding a group's list, in the group's room (the space, or a
/// group chat outside a space), state key `''`. Content:
/// `{"replacements": [{"from": ":)", "to": "🙂"}, ...]}`. While the room has
/// none, [defaultTextReplacements] apply.
const String gruppechatTextReplacementsType = 'im.gruppechat.text_replacements';

/// The replacements used where a group has no list of its own.
const List<TextReplacement> defaultTextReplacements = [
  TextReplacement(':)', '🙂'),
  TextReplacement(':-)', '🙂'),
  TextReplacement(':(', '🙁'),
  TextReplacement(':-(', '🙁'),
];

/// Who may set a group's list: moderators and admins.
const int textReplacementsPowerLevel = 50;

// Safety caps, so one list can't grow past what a state event holds
const int maxTextReplacementFromLength = 32;
const int maxTextReplacementToLength = 200;
const int maxTextReplacements = 100;

final RegExp _whitespace = RegExp(r'\s');

/// One rule: the word [from], typed on its own and in any case, becomes [to].
/// Only whitespace ends a word, so `mvh.` is left as it is.
class TextReplacement {
  final String from;
  final String to;

  const TextReplacement(this.from, this.to);

  /// Whether [from] is a single word of at most
  /// [maxTextReplacementFromLength] characters and [to] isn't empty, too
  /// long (counting characters as the text fields do) or a command.
  bool get isValid =>
      from.isNotEmpty &&
      from.characters.length <= maxTextReplacementFromLength &&
      !from.contains(_whitespace) &&
      to.trim().isNotEmpty &&
      // A replacement must never turn a message into a command like `/op`
      !to.trimLeft().startsWith('/') &&
      to.characters.length <= maxTextReplacementToLength;

  Map<String, Object?> toJson() => {'from': from, 'to': to};

  @override
  bool operator ==(Object other) =>
      other is TextReplacement && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => '$from → $to';
}

/// The list in [content] of a [gruppechatTextReplacementsType] event, or the
/// defaults when there is none. Invalid rules are left out, and for a word
/// listed twice the first rule counts.
List<TextReplacement> parseTextReplacements(Map<String, Object?>? content) {
  final raw = content?['replacements'];
  if (raw is! List) return defaultTextReplacements;
  final seen = <String>{};
  // Case is ignored when matching, so a word counts once in any case
  final rules = <TextReplacement>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final from = item['from'];
    final to = item['to'];
    if (from is! String || to is! String) continue;
    final rule = TextReplacement(from, to);
    if (!rule.isValid || !seen.add(from.toLowerCase())) continue;
    rules.add(rule);
    if (rules.length >= maxTextReplacements) break;
  }
  return rules;
}

/// Content for a [gruppechatTextReplacementsType] event holding [rules].
Map<String, Object?> textReplacementsContent(List<TextReplacement> rules) => {
  'replacements': [for (final rule in rules) rule.toJson()],
};

/// [rules] with [rule] added, replacing any rule for the same word.
List<TextReplacement> withTextReplacement(
  List<TextReplacement> rules,
  TextReplacement rule,
) => [
  for (final other in rules)
    if (other.from.toLowerCase() != rule.from.toLowerCase()) other,
  rule,
];

/// The replacement for [word], ignoring case, as phones capitalise the first
/// word of a message.
String? _replacementFor(List<TextReplacement> rules, String word) {
  final lower = word.toLowerCase();
  for (final rule in rules) {
    if (rule.from.toLowerCase() == lower) return rule.to;
  }
  return null;
}

/// Where the word ending at [end] in [text] starts.
int _wordStart(String text, int end) {
  var start = end;
  while (start > 0 && !_isSpace(text.codeUnitAt(start - 1))) {
    start--;
  }
  return start;
}

bool _isSpace(int codeUnit) =>
    codeUnit == 0x20 ||
    codeUnit == 0x0A ||
    codeUnit == 0x09 ||
    codeUnit == 0x0D ||
    codeUnit == 0xA0;

/// Replaces words in the chat's input field as people type: a space typed
/// right after a word in the list turns the word into its replacement, and a
/// backspace straight after brings back what was typed. Only typing goes
/// through a formatter, so text the app sets itself is left alone.
class GruppechatTextReplacer extends TextInputFormatter {
  /// The rules for the chat, asked for only when a space is typed.
  final List<TextReplacement> Function() rules;

  GruppechatTextReplacer(this.rules);

  /// The value this formatter last returned after replacing a word, and the
  /// word it replaced, so a backspace can undo it.
  ({TextEditingValue value, String word, int start})? _last;

  /// The text after the last undo, so sending it doesn't replace again.
  String? _undoneText;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Moving the cursor or composing changes nothing to remember
    if (oldValue.text == newValue.text) return newValue;
    final last = _last;
    _last = null;
    _undoneText = null;

    if (last != null &&
        oldValue.text == last.value.text &&
        oldValue.selection == last.value.selection &&
        _isBackspaceOfSpace(oldValue, newValue)) {
      final (:start, :word, value: _) = last;
      final end = newValue.selection.baseOffset;
      final text = newValue.text.replaceRange(start, end, word);
      _undoneText = text;
      return TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: start + word.length),
      );
    }

    if (!_isTypedSpace(oldValue, newValue)) return newValue;
    final spaceAt = newValue.selection.baseOffset - 1;
    final start = _wordStart(newValue.text, spaceAt);
    if (start == spaceAt) return newValue;
    final typed = newValue.text.substring(start, spaceAt);
    final replacement = _replacementFor(rules(), typed);
    if (replacement == null) return newValue;
    final text = newValue.text.replaceRange(start, spaceAt, replacement);
    final result = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: start + replacement.length + 1,
      ),
    );
    _last = (value: result, word: typed, start: start);
    return result;
  }

  /// [text] as it should be sent: a list word at its very end is replaced
  /// too, as no space follows it, unless a backspace just brought it back.
  String onSend(String text) {
    if (text == _undoneText) return text;
    final end = text.length;
    final start = _wordStart(text, end);
    if (start == end) return text;
    final replacement = _replacementFor(rules(), text.substring(start));
    if (replacement == null) return text;
    return text.replaceRange(start, end, replacement);
  }

  static bool _isTypedSpace(TextEditingValue oldValue, TextEditingValue n) {
    if (n.composing.isValid && !n.composing.isCollapsed) return false;
    if (!n.selection.isCollapsed || !oldValue.selection.isCollapsed) {
      return false;
    }
    final cursor = n.selection.baseOffset;
    if (cursor < 1 || n.text.length != oldValue.text.length + 1) return false;
    if (oldValue.selection.baseOffset != cursor - 1) return false;
    if (n.text.codeUnitAt(cursor - 1) != 0x20) return false;
    return n.text.substring(0, cursor - 1) ==
            oldValue.text.substring(0, cursor - 1) &&
        n.text.substring(cursor) == oldValue.text.substring(cursor - 1);
  }

  static bool _isBackspaceOfSpace(
    TextEditingValue oldValue,
    TextEditingValue n,
  ) {
    if (!n.selection.isCollapsed || !oldValue.selection.isCollapsed) {
      return false;
    }
    final cursor = oldValue.selection.baseOffset;
    if (cursor < 1 || n.text.length != oldValue.text.length - 1) return false;
    if (n.selection.baseOffset != cursor - 1) return false;
    if (oldValue.text.codeUnitAt(cursor - 1) != 0x20) return false;
    return n.text ==
        oldValue.text.substring(0, cursor - 1) +
            oldValue.text.substring(cursor);
  }
}

/// Whether a message typed as [typed] and sent as [sent] may run as a
/// command like `/op`: only when the person typed one, never because a
/// replacement made the message start with `/`.
bool gruppechatMayRunCommand(String typed, String sent) =>
    !sent.startsWith('/') || typed.startsWith('/');
