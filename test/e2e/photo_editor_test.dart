// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Wish for 1.1.43 (Martin): more tools in the photo editor. Before sending a
// photo, it can be given a filter (black and white, sepia, …) and its
// brightness, contrast and saturation changed, in the editor of
// lib/pages/chat/send_file_dialog.dart with lib/gruppechat/photo_looks.dart.
// How the controls feel, and their speed on big photos, can only be tried
// on a phone.

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

/// An orange photo, which black and white turns grey.
Uint8List orangePhoto(int width, int height) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(230, 120, 20));
  return img.encodePng(image);
}

void main() {
  group('Photo editor', skip: skipWithoutTestServer, () {
    late Room aliceChat;
    late Timeline bobTimeline;
    late XFile picked;

    setUpAll(() async {
      final folder = await Directory.systemTemp.createTemp('foto');
      addTearDown(() => folder.delete(recursive: true));
      final file = File('${folder.path}/solnedgang.png');
      await file.writeAsBytes(orangePhoto(400, 300));
      picked = XFile(file.path, mimeType: 'image/png');

      // Widget tests block the network; these talk to the test server
      HttpOverrides.global = null;
      final alice = await logIn('alice');
      final bob = await logIn('bob');
      final (mine, theirs) = await directChat(alice, bob);
      aliceChat = mine;
      bobTimeline = await theirs.getTimeline();
    });
    tearDownAll(logOutEveryone);

    testWidgets('Alice sends a photo in black and white, and Bob gets it so', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await AppSettings.init(loadWebConfigFile: false);
      await AppSettings.reset(loadWebConfigFile: false);
      addTearDown(() => AppSettings.reset(loadWebConfigFile: false));
      await tester.binding.setSurfaceSize(const Size(500, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Decoding, painting and the server work in real time while the
      // widgets move on
      Future<void> wait(bool Function() done) async {
        for (var i = 0; i < 600 && !done(); i++) {
          await tester.pump(const Duration(milliseconds: 50));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
        }
      }

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAdaptiveDialog<bool>(
                  context: context,
                  builder: (_) => SendFileDialog(
                    room: aliceChat,
                    files: [picked],
                    outerContext: context,
                    threadLastEventId: null,
                    threadRootEventId: null,
                  ),
                ),
                child: const Text('Bilete'),
              ),
            ),
          ),
        ),
      );
      await wait(() => find.text('Bilete').evaluate().isNotEmpty);
      await tester.tap(find.text('Bilete'));
      await wait(() => find.byType(SendFileDialog).evaluate().isNotEmpty);
      final l10n = L10n.of(tester.element(find.byType(SendFileDialog)));

      // She opens the editor, draws a red line across the middle, and picks
      // black and white under «Filter»
      await wait(() => find.byTooltip(l10n.editImage).evaluate().isNotEmpty);
      await tester.tap(find.byTooltip(l10n.editImage));
      await wait(
        () => find.text(l10n.gruppechatPhotoFilter).evaluate().isNotEmpty,
      );
      await tester.tap(find.text(l10n.draw));
      await tester.pump();
      final surface = tester.getCenter(find.byType(InteractiveViewer));
      final pen = await tester.startGesture(surface - const Offset(80, 0));
      for (var x = -70; x <= 80; x += 10) {
        await pen.moveTo(surface + Offset(x.toDouble(), 0));
      }
      await pen.up();
      await tester.pump();
      await tester.tap(find.text(l10n.gruppechatPhotoFilter));
      await wait(
        () => find.text(l10n.gruppechatLookBlackWhite).evaluate().isNotEmpty,
      );
      await tester.tap(find.text(l10n.gruppechatLookBlackWhite));
      await tester.pump();
      await tester.tap(find.byTooltip(l10n.save));
      await wait(
        () => find.text(l10n.gruppechatPhotoFilter).evaluate().isEmpty,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.text(l10n.send));
      Event? arrived() => bobTimeline.events.firstWhereOrNull(
        (e) =>
            e.messageType == MessageTypes.Image && e.body == 'solnedgang.png',
      );
      await wait(() => arrived() != null);
      expect(arrived(), isNotNull, reason: 'bob gets the photo');

      img.Image? sent;
      await tester.runAsync(() async {
        sent = img.decodeImage(
          (await arrived()!.downloadAndDecryptAttachment()).bytes,
        );
      });
      // Not cut: the same shape. (The test's client resizes with the SDK's
      // default, which also enlarges small photos; the app's doesn't.)
      expect(sent!.width / sent!.height, closeTo(4 / 3, 0.01));
      // The photo is grey: red, green and blue alike, where they were far
      // apart
      final photo = sent!.getPixel(sent!.width ~/ 2, sent!.height ~/ 4);
      expect((photo.r - photo.g).abs(), lessThan(4));
      expect((photo.g - photo.b).abs(), lessThan(4));
      // The line she drew is still red
      final ink = sent!.getPixel(sent!.width ~/ 2, sent!.height ~/ 2);
      // (its edges blend with the grey when the photo is resized)
      expect(ink.r - ink.g, greaterThan(100));
      expect(ink.r - ink.b, greaterThan(100));

      // The «sending» notice goes once all is out
      await wait(() => find.byType(SnackBar).evaluate().isEmpty);
      // Time-outs of the requests run out without anything left to do
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(seconds: 10));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
      }
    });
  });
}
