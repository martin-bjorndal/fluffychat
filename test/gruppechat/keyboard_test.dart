// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// What text fields ask of the phone's keyboard: fields where people write
// sentences start each sentence with a capital letter, like the chat field
// does, and search fields don't offer saved usernames. Whether the keyboard
// then does it can only be seen on a phone.

import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:fluffychat/gruppechat/gif_picker.dart';
import 'package:fluffychat/gruppechat/giphy.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/send_file_dialog.dart';
import 'package:fluffychat/pages/chat/start_poll_bottom_sheet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../utils/test_client.dart';

void main() {
  const phones = TargetPlatformVariant({
    TargetPlatform.android,
    TargetPlatform.iOS,
  });
  late Room room;
  setUpAll(() async {
    room = Room(id: '!chat:example.invalid', client: await prepareTestClient());
  });

  Future<void> open(
    WidgetTester tester,
    Widget page, {
    bool settle = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: page,
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      // The texts load first
      for (
        var i = 0;
        i < 10 && find.byType(EditableText).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
  }

  List<TextCapitalization> fields(WidgetTester tester) => tester
      .widgetList<EditableText>(find.byType(EditableText))
      .map((field) => field.textCapitalization)
      .toList();

  testWidgets('a caption starts with a capital letter', variant: phones, (
    tester,
  ) async {
    await open(
      tester,
      Builder(
        builder: (context) => SendFileDialog(
          room: room,
          files: [
            XFile.fromData(
              Uint8List.fromList(List.filled(100, 1)),
              name: 'handleliste.pdf',
              mimeType: 'application/pdf',
            ),
          ],
          outerContext: context,
          threadLastEventId: null,
          threadRootEventId: null,
        ),
      ),
    );
    expect(fields(tester), [TextCapitalization.sentences]);
  });

  testWidgets(
    'a poll question and its answers start with capitals',
    variant: phones,
    (tester) async {
      await open(tester, StartPollBottomSheet(room: room));
      expect(fields(tester), hasLength(3));
      expect(fields(tester), everyElement(TextCapitalization.sentences));
    },
  );

  testWidgets('the GIF search offers no saved usernames', variant: phones, (
    tester,
  ) async {
    // The search spins while it waits for GIFs, so it never settles
    await open(
      tester,
      Scaffold(body: GifPicker(giphy: Giphy(room.client))),
      settle: false,
    );
    final search = tester.widget<EditableText>(find.byType(EditableText));
    expect(search.autofillHints, isNull);
    // Let the search's request time out
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  });
}
