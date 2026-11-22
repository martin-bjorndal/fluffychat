// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/gruppechat/text_replacements.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TextEditingValue _at(String text, [int? cursor]) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: cursor ?? text.length),
);

/// Types [chars] one by one at the end of [start], as a keyboard would.
TextEditingValue _type(
  GruppechatTextReplacer replacer,
  TextEditingValue start,
  String chars,
) {
  var value = start;
  for (final char in chars.split('')) {
    final cursor = value.selection.baseOffset;
    final next = _at(
      value.text.replaceRange(cursor, cursor, char),
      cursor + char.length,
    );
    value = replacer.formatEditUpdate(value, next);
  }
  return value;
}

TextEditingValue _backspace(
  GruppechatTextReplacer replacer,
  TextEditingValue value,
) {
  final cursor = value.selection.baseOffset;
  final chars = value.text.substring(0, cursor).characters;
  final before = chars.skipLast(1).toString();
  return replacer.formatEditUpdate(
    value,
    _at(before + value.text.substring(cursor), before.length),
  );
}

void main() {
  group('parseTextReplacements', () {
    test('a group without a list gets :) and :( as emojis', () {
      expect(parseTextReplacements(null), defaultTextReplacements);
      expect(parseTextReplacements({}), defaultTextReplacements);
      expect(
        defaultTextReplacements,
        containsAll(const [
          TextReplacement(':)', '🙂'),
          TextReplacement(':(', '🙁'),
        ]),
      );
    });

    test('a group\'s list is the whole list, without bad or repeated '
        'rules', () {
      final rules = parseTextReplacements({
        'replacements': [
          {'from': 'mvh', 'to': 'med vennleg helsing'},
          {'from': 'mvh', 'to': 'second'},
          {'from': 'two words', 'to': 'x'},
          {'from': 'empty', 'to': ' '},
          {'from': 'x' * 33, 'to': 'long'},
          {'from': 1, 'to': 'x'},
          // A replacement may never turn a message into a command
          {'from': 'ok', 'to': '/leave'},
          {'from': 'ja', 'to': '  /op @x:y 100'},
          'junk',
        ],
      });
      expect(rules, const [TextReplacement('mvh', 'med vennleg helsing')]);
      expect(parseTextReplacements({'replacements': []}), isEmpty);
      // Characters count as the text fields count them
      expect(TextReplacement('🙂' * 20, 'x').isValid, isTrue);
      expect(TextReplacement('mvh', '🙂' * 200).isValid, isTrue);
    });

    test('content round-trips, and adding replaces the same word', () {
      final rules = withTextReplacement(
        defaultTextReplacements,
        const TextReplacement(':)', '😀'),
      );
      expect(rules.where((r) => r.from == ':)').single.to, '😀');
      expect(parseTextReplacements(textReplacementsContent(rules)), rules);
    });
  });

  group('GruppechatTextReplacer', () {
    late GruppechatTextReplacer replacer;
    setUp(
      () => replacer = GruppechatTextReplacer(
        () => [
          ...defaultTextReplacements,
          const TextReplacement('mvh', 'med vennleg helsing'),
        ],
      ),
    );

    test('a space after :) makes it 🙂', () {
      final value = _type(replacer, _at(''), 'hei :) ');
      expect(value.text, 'hei 🙂 ');
      expect(value.selection.baseOffset, value.text.length);
      expect(_type(replacer, value, 'ok :( ').text, 'hei 🙂 ok 🙁 ');
    });

    test('a space in the middle of the text replaces the word before it', () {
      final value = replacer.formatEditUpdate(
        _at('a mvhb', 5),
        _at('a mvh b', 6),
      );
      expect(value.text, 'a med vennleg helsing b');
      expect(value.selection.baseOffset, 'a med vennleg helsing '.length);
    });

    test('only whole words are replaced', () {
      expect(_type(replacer, _at(''), 'f:) ').text, 'f:) ');
      expect(_type(replacer, _at(''), 'mvhx ').text, 'mvhx ');
      expect(_type(replacer, _at(''), 'hei  ').text, 'hei  ');
    });

    test('backspace right after brings back what was typed', () {
      var value = _type(replacer, _at(''), 'hei :) ');
      value = _backspace(replacer, value);
      expect(value.text, 'hei :)');
      expect(value.selection.baseOffset, 6);
      // A second backspace is an ordinary one
      expect(_backspace(replacer, value).text, 'hei :');
    });

    test('backspace after something else is an ordinary one', () {
      var value = _type(replacer, _at(''), ':) a');
      value = _backspace(replacer, value);
      value = _backspace(replacer, value);
      expect(value.text, '🙂');
    });

    test('text the app set itself is not undone', () {
      _type(replacer, _at(''), ':) ');
      // The app empties the field and sets a draft "x 🙂 "
      final value = replacer.formatEditUpdate(_at('x 🙂 '), _at('x 🙂'));
      expect(value.text, 'x 🙂');
    });

    test('nothing happens while the keyboard is composing', () {
      final value = replacer.formatEditUpdate(
        _at(':)'),
        const TextEditingValue(
          text: ':) ',
          selection: TextSelection.collapsed(offset: 3),
          composing: TextRange(start: 0, end: 3),
        ),
      );
      expect(value.text, ':) ');
    });

    test('a list word at the very end is replaced on sending', () {
      expect(replacer.onSend('hei :)'), 'hei 🙂');
      expect(replacer.onSend('hei'), 'hei');
      expect(replacer.onSend('hei :) '), 'hei :) ');
      expect(replacer.onSend(''), '');
    });

    test('but not when a backspace just brought it back', () {
      var value = _type(replacer, _at(''), 'hei :) ');
      value = _backspace(replacer, value);
      expect(replacer.onSend(value.text), 'hei :)');
      value = _type(replacer, value, 'x');
      expect(replacer.onSend(value.text), 'hei :)x');
    });

    testWidgets('typing in a text field with it', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: TextField(
              controller: controller,
              inputFormatters: [replacer],
            ),
          ),
        ),
      );
      await tester.showKeyboard(find.byType(TextField));
      for (final text in ['h', 'he', 'hei', 'hei ', 'hei :', 'hei :)']) {
        tester.testTextInput.updateEditingValue(_at(text));
        await tester.pump();
      }
      tester.testTextInput.updateEditingValue(_at('hei :) '));
      await tester.pump();
      expect(controller.text, 'hei 🙂 ');
      tester.testTextInput.updateEditingValue(_at('hei 🙂'));
      await tester.pump();
      expect(controller.text, 'hei :)');
    });
  });
}
