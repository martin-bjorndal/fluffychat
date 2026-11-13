// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Wishes from 1.1.23: patterns and own colours for a chat's background, a
// gallery button in the input bar, and Enter sending a pasted picture on a
// computer. How the patterns look, and the gallery picker itself, can only
// be judged on a phone.

import 'package:cross_file/cross_file.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/gruppechat/background_picker.dart';
import 'package:fluffychat/gruppechat/chat_colors.dart';
import 'package:fluffychat/gruppechat/gallery_button.dart';
import 'package:fluffychat/gruppechat/group_state.dart';
import 'package:fluffychat/gruppechat/group_widgets.dart';
import 'package:fluffychat/gruppechat/matrix_group.dart';
import 'package:fluffychat/gruppechat/send_on_enter.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/send_file_dialog.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/test_client.dart';

void main() {
  Future<void> open(
    WidgetTester tester,
    Widget page, {
    bool settle = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(body: page),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      // The texts load first
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
  }

  group('backgrounds', () {
    testWidgets('every pattern draws', (tester) async {
      for (final pattern in GroupBackgroundPattern.values) {
        await open(
          tester,
          GroupBackgroundLayer(
            background: GroupBackground(
              kind: GroupBackgroundKind.pattern,
              pattern: pattern,
              colors: const [0xFFFFEBF0, 0xFFF48FB1],
              opacity: 0.6,
            ),
          ),
        );
        expect(tester.takeException(), isNull, reason: pattern.name);
        final paint = tester.widget<CustomPaint>(
          find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is GroupPatternPainter,
          ),
        );
        expect((paint.painter! as GroupPatternPainter).pattern, pattern);
      }
    });

    Future<GroupBackground?> pick(
      WidgetTester tester,
      Future<void> Function() choose, {
      GroupBackground? current,
    }) async {
      GroupBackground? result;
      await open(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showBackgroundColorsDialog(
              context: context,
              current: current,
            ),
            child: const Text('Bakgrunn'),
          ),
        ),
      );
      await tester.tap(find.text('Bakgrunn'));
      await tester.pumpAndSettle();
      await choose();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('a ready-made one is picked from its preview', (tester) async {
      final hearts = groupBackgroundPresets.firstWhere(
        (preset) => preset.$1 == 'Hearts',
      );
      final result = await pick(tester, () async {
        await tester.tap(find.byTooltip('Hearts'));
        await tester.pumpAndSettle();
      });
      expect(result, same(hearts.$2));
    });

    testWidgets('people make their own pattern', (tester) async {
      final result = await pick(tester, () async {
        await tester.tap(find.text('Pattern'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Flowers').last);
        await tester.tap(find.text('Flowers').last);
        await tester.pumpAndSettle();
      }, current: groupBackgroundPresets.first.$2);
      expect(result!.kind, GroupBackgroundKind.pattern);
      expect(result.pattern, GroupBackgroundPattern.flowers);
      expect(result.colors.first, groupBackgroundPresets.first.$2.colors.first);
      expect(result.isValid, isTrue);
    });

    test('a picture background starts the picker from a preset', () {
      final picture = GroupBackground(
        kind: GroupBackgroundKind.image,
        url: Uri.parse('mxc://example.invalid/bilde'),
      );
      expect(backgroundToEdit(picture), groupBackgroundPresets.first.$2);
      expect(backgroundToEdit(null), groupBackgroundPresets.first.$2);
    });
  });

  testWidgets('the gallery button opens the gallery', (tester) async {
    var opened = 0;
    await open(
      tester,
      GruppechatGalleryButton(
        hidden: false,
        height: 48,
        onPressed: () => opened++,
      ),
    );
    await tester.tap(find.byTooltip('Open gallery'));
    expect(opened, 1);
    // While people write, it makes room, as the + does
    await open(
      tester,
      GruppechatGalleryButton(
        hidden: true,
        height: 48,
        onPressed: () => opened++,
      ),
    );
    expect(tester.getSize(find.byType(GruppechatGalleryButton)).width, 0);
  });

  group('Enter sends', () {
    late Room room;
    setUpAll(() async {
      room = Room(
        id: '!chat:example.invalid',
        client: await prepareTestClient(),
      );
    });
    late int sent;
    Future<void> openDialog(WidgetTester tester) async {
      sent = 0;
      await open(
        tester,
        GruppechatSendOnEnter(
          onSend: () => sent++,
          child: ListView(
            children: [
              const TextField(key: Key('caption')),
              TextButton(onPressed: () {}, child: const Text('Avbryt')),
            ],
          ),
        ),
      );
    }

    testWidgets('right after pasting', (tester) async {
      await openDialog(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(sent, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
      expect(sent, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      expect(sent, 2);
    });

    testWidgets('unless "send with Enter" is off', (tester) async {
      sent = 0;
      await open(
        tester,
        GruppechatSendOnEnter(
          enabled: false,
          onSend: () => sent++,
          child: const SizedBox(),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(sent, 0);
    });

    testWidgets('after clicking beside the message field', (tester) async {
      await openDialog(tester);
      await tester.tap(find.byKey(const Key('caption')));
      // As the field does when people click beside it
      FocusManager.instance.primaryFocus!.unfocus();
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, isA<FocusScopeNode>());
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(sent, 1);
    });

    testWidgets('from the message field, but not with Shift', (tester) async {
      await openDialog(tester);
      await tester.tap(find.byKey(const Key('caption')));
      await tester.enterText(find.byKey(const Key('caption')), 'Se her');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(sent, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(sent, 1);
    });

    testWidgets('not on a focused button', (tester) async {
      await openDialog(tester);
      Focus.of(tester.element(find.text('Avbryt'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(sent, 0);
    });

    bool dialogTakesFocus(WidgetTester tester) => tester
        .widget<Focus>(
          find
              .descendant(
                of: find.byType(GruppechatSendOnEnter),
                matching: find.byType(Focus),
              )
              .first,
        )
        .autofocus;

    // PDFs, since a picture's preview doesn't load in a widget test
    Future<void> paste(
      WidgetTester tester, {
      required bool sendOnEnter,
      int files = 1,
    }) async {
      SharedPreferences.setMockInitialValues({});
      await AppSettings.init(loadWebConfigFile: false);
      await AppSettings.reset(loadWebConfigFile: false);
      addTearDown(() => AppSettings.reset(loadWebConfigFile: false));
      await AppSettings.sendOnEnter.setItem(sendOnEnter);
      await open(
        tester,
        Builder(
          builder: (context) => SendFileDialog(
            room: room,
            files: [
              for (var i = 0; i < files; i++)
                XFile.fromData(
                  Uint8List.fromList(List.filled(100, 1)),
                  name: 'skjermbilde$i.pdf',
                  mimeType: 'application/pdf',
                ),
            ],
            outerContext: context,
            threadLastEventId: null,
            threadRootEventId: null,
          ),
        ),
        settle: false,
      );
    }

    testWidgets('in the dialog for pasted files', (tester) async {
      // Several files have no message field
      await paste(tester, sendOnEnter: true, files: 2);
      expect(find.byType(GruppechatSendOnEnter), findsOneWidget);
      // The dialog has the focus as it opens, so Enter reaches it
      expect(dialogTakesFocus(tester), isTrue);
    });

    // Bug from 1.1.30: after pasting a picture on a computer, people want to
    // write a message at once and send it with Enter
    EditableText? focusedField() => FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<EditableText>();

    // On a Mac, the browser draws the dialog's field as on an iPhone
    testWidgets(
      'the message field has the focus after pasting',
      variant: const TargetPlatformVariant({
        TargetPlatform.windows,
        TargetPlatform.macOS,
      }),
      (tester) async {
        await paste(tester, sendOnEnter: true);
        expect(focusedField(), isNotNull);
        expect(dialogTakesFocus(tester), isFalse);
        // What people type goes into the message; Enter from a field sends,
        // as "from the message field" tests
        tester.testTextInput.enterText('Se her');
        await tester.pump();
        expect(focusedField()!.controller.text, 'Se her');
      },
    );

    testWidgets('but not where Enter makes a new line, as on phones', (
      tester,
    ) async {
      await paste(tester, sendOnEnter: false);
      expect(focusedField(), isNull);
      expect(dialogTakesFocus(tester), isTrue);
    });
  });

  // Wish from 1.1.26: a chat's own colours for its bars and bubbles, not its
  // background
  group('chat colours', () {
    test('are read solid, and nothing else counts', () {
      expect(parseChatColor({'color': '#E91E63'}), 0xFFE91E63);
      expect(parseChatColor({'color': '#00E91E63'}), 0xFFE91E63);
      expect(parseChatColor({}), isNull);
      expect(parseChatColor({'color': 'rosa'}), isNull);
      expect(parseChatColor(null), isNull);
    });

    for (final brightness in Brightness.values) {
      testWidgets('colour the bars and bubbles in $brightness, not the '
          'background', (tester) async {
        late ThemeData base;
        late ThemeData chat;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                base = FluffyThemes.buildTheme(context, brightness);
                chat = gruppechatChatTheme(
                  context,
                  base,
                  const Color(0xFF00897B),
                );
                return const SizedBox();
              },
            ),
          ),
        );
        final bars = chat.extension<GruppechatChatColors>()!;
        expect(chat.brightness, brightness);
        expect(chat.bubbleColor, isNot(base.bubbleColor));
        expect(chat.colorScheme.surface, base.colorScheme.surface);
        expect(chat.scaffoldBackgroundColor, base.scaffoldBackgroundColor);
        expect(chat.dividerColor, base.dividerColor);
        expect(bars.bar, isNot(chat.bubbleColor));
        expect(bars.bar, isNot(chat.colorScheme.secondaryContainer));
        expect(bars.bar, isNot(base.colorScheme.surfaceContainer));
        // The bar's text stands out from it
        final contrast =
            (bars.bar.computeLuminance() - bars.onBar.computeLuminance()).abs();
        expect(contrast, greaterThan(0.3));
      });
    }

    late Client client;
    setUpAll(() async => client = await prepareTestClient(loggedIn: true));

    testWidgets('a chat takes its colour, and loses it again', (tester) async {
      final room = Room(id: '!gruppe:example.invalid', client: client);
      void setColor(Map<String, Object?> content) => room.setState(
        StrippedStateEvent(
          type: GruppechatEventTypes.chatColor,
          content: content,
          senderId: client.userID!,
          stateKey: room.id,
        ),
      );
      ThemeData? seen;
      Future<void> show() => tester.pumpWidget(
        MaterialApp(
          home: GruppechatChatColorTheme(
            room: room,
            child: Builder(
              builder: (context) {
                seen = Theme.of(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      await show();
      expect(seen!.extension<GruppechatChatColors>(), isNull);
      setColor({'color': '#E91E63'});
      expect(room.gruppechatChatColor, 0xFFE91E63);
      await show();
      expect(seen!.extension<GruppechatChatColors>(), isNotNull);
      setColor({});
      await show();
      expect(seen!.extension<GruppechatChatColors>(), isNull);
    });
  });
}
