// SPDX-FileCopyrightText: 2026 Gruppechat contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/settings_chat/settings_chat.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // Tor Helge: the bottom of the settings went white, though it still
  // scrolled. The sound volume tile used Flutter's own material library,
  // whose ListTile finds no Material of its own in the app's material_ui
  // pages, so it failed and nothing below it was drawn.
  testWidgets('the chat settings draw all the way down on a phone', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: SettingsChat(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.dragUntilVisible(
      find.text('Calls'),
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('gruppechat_sound_volume')), findsOneWidget);
    expect(find.text('Custom emojis and stickers'), findsWidgets);
  });

  test('our widgets come from material_ui, as the app pages do', () {
    final flutterMaterial = RegExp(
      r"""^\s*(import|export)\s+['"]package:flutter/material\.dart['"]""",
      multiLine: true,
    );
    final mixed = [
      for (final file in Directory('lib/gruppechat').listSync(recursive: true))
        if (file is File &&
            file.path.endsWith('.dart') &&
            flutterMaterial.hasMatch(file.readAsStringSync()))
          file.path,
    ];
    expect(mixed, isEmpty);
  });
}
