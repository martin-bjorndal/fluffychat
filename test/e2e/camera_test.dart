// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Bug from 1.1.41 (Tor Helge): pressing «Send» on a photo from the camera
// showed "Null check operator used on a null value", and the photo was not
// sent. When the camera hands the photo back and the phone has turned, the
// chat is built anew behind the send dialog
// (lib/pages/chat/send_file_dialog.dart). The camera itself, and turning a
// phone, can only be tried on a phone.

@Timeout(Duration(minutes: 3))
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:cross_file/cross_file.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/send_file_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/test_server.dart';

Uint8List photo(int width, int height) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(30, 120, 200));
  return img.encodePng(image);
}

void main() {
  group('Camera', skip: skipWithoutTestServer, () {
    late Room aliceChat;
    late Timeline bobTimeline;
    // The camera hands back a file it saved
    late XFile taken;

    setUpAll(() async {
      final folder = await Directory.systemTemp.createTemp('kamera');
      addTearDown(() => folder.delete(recursive: true));
      final file = File('${folder.path}/kamera.png');
      await file.writeAsBytes(photo(400, 300));
      taken = XFile(file.path, mimeType: 'image/png');

      // Widget tests block the network; these talk to the test server
      HttpOverrides.global = null;
      final alice = await logIn('alice');
      final bob = await logIn('bob');
      final (mine, theirs) = await directChat(alice, bob);
      aliceChat = mine;
      bobTimeline = await theirs.getTimeline();
    });
    tearDownAll(logOutEveryone);

    testWidgets(
      'a photo from the camera is sent though the chat was rebuilt behind it',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await AppSettings.init(loadWebConfigFile: false);
        await AppSettings.reset(loadWebConfigFile: false);
        addTearDown(() => AppSettings.reset(loadWebConfigFile: false));

        // The server works in real time while the widgets move on
        Future<void> wait(bool Function() done) async {
          for (var i = 0; i < 600 && !done(); i++) {
            await tester.pump(const Duration(milliseconds: 50));
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 50)),
            );
          }
        }

        Widget app(Orientation orientation) => MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: _CameraChat(
              key: ValueKey(orientation),
              room: aliceChat,
              photo: taken,
            ),
          ),
        );
        await tester.pumpWidget(app(Orientation.portrait));
        await wait(() => find.text('Kamera').evaluate().isNotEmpty);
        await tester.tap(find.text('Kamera'));
        await wait(() => find.byType(SendFileDialog).evaluate().isNotEmpty);

        // The phone turned while the camera was open
        await tester.pumpWidget(app(Orientation.landscape));
        await tester.pump();
        expect(find.byType(SendFileDialog), findsOneWidget);

        final l10n = L10n.of(tester.element(find.byType(SendFileDialog)));
        await tester.tap(find.text(l10n.send));
        Event? arrived() => bobTimeline.events.firstWhereOrNull(
          (e) => e.messageType == MessageTypes.Image && e.body == 'kamera.png',
        );
        await wait(() => arrived() != null);
        expect(tester.takeException(), isNull);
        expect(find.byType(SendFileDialog), findsNothing);
        expect(arrived(), isNotNull, reason: 'bob gets the photo');
        // The «sending» notice goes once all is out
        await wait(() => find.byType(SnackBar).evaluate().isEmpty);
        expect(find.byType(SnackBar), findsNothing);
        // Time-outs of the requests run out without anything left to do
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(seconds: 10));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
        }
      },
    );
  });
}

/// Stands in for the chat page: opens the send dialog with its own context,
/// as the chat does after taking a photo (openCameraAction in chat.dart).
class _CameraChat extends StatefulWidget {
  final Room room;
  final XFile photo;
  const _CameraChat({required this.room, required this.photo, super.key});

  @override
  State<_CameraChat> createState() => _CameraChatState();
}

class _CameraChatState extends State<_CameraChat> {
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => showAdaptiveDialog<bool>(
      context: context,
      builder: (_) => SendFileDialog(
        room: widget.room,
        files: [widget.photo],
        outerContext: context,
        threadLastEventId: null,
        threadRootEventId: null,
      ),
    ),
    child: const Text('Kamera'),
  );
}
