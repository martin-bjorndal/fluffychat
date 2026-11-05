// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// In a call, the menu's choices open a list of devices, such as the phone's
// speaker or a Bluetooth headset. The list must open after the menu closes.

import 'package:fluffychat/gruppechat/call_devices.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/position_from_build_context.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('choosing the speaker opens the list of speakers', (
    tester,
  ) async {
    // As CallViewModel.selectSpeaker: it asks the phone for its speakers,
    // then shows them next to the button
    Future<void> selectSpeaker(BuildContext context) async {
      await Future<void>.delayed(Duration.zero);
      if (!context.mounted) return;
      await showMenu<String>(
        context: context,
        position: context.position,
        items: const [
          PopupMenuItem(value: 'speaker', child: Text('Høyttaler')),
          PopupMenuItem(value: 'bluetooth', child: Text('Bluetooth')),
        ],
      );
    }

    Future<void> nothing(BuildContext context) async {}

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          appBar: AppBar(
            actions: [
              GruppechatCallDeviceMenu(
                selectCamera: nothing,
                selectMicrophone: nothing,
                selectSpeaker: selectSpeaker,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<void>));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.speaker_phone_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Høyttaler'), findsOneWidget);
    expect(find.text('Bluetooth'), findsOneWidget);
  });
}
