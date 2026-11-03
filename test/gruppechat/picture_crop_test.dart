// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

import 'package:fluffychat/gruppechat/picture_crop.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';

void main() {
  Uint8List photo({required bool png}) {
    final image = img.Image(width: 400, height: 200)
      ..clear(img.ColorRgb8(200, 80, 40));
    return png ? img.encodePng(image) : img.encodeJpg(image);
  }

  test('cropped pictures are named after their format', () {
    expect(croppedPictureName('avatar', photo(png: true)), 'avatar.png');
    expect(croppedPictureName('avatar', photo(png: false)), 'avatar.jpg');
  });

  /// Opens the crop page for [bytes], saves at once and returns the picture.
  Future<img.Image> cropAndSave(
    WidgetTester tester,
    Uint8List bytes,
    PictureCrop crop,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    Uint8List? result;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showPictureCrop(
              context,
              bytes: bytes,
              crop: crop,
            ),
            child: const Text('pick'),
          ),
        ),
      ),
    );
    // The texts load first
    await tester.pumpAndSettle();
    await tester.tap(find.text('pick'));
    // The picture decodes, and is cropped and encoded, outside the fake
    // clock; a spinner shows meanwhile, so the page never settles
    Future<void> waitWhile(bool Function() busy) async {
      for (var i = 0; i < 50 && busy(); i++) {
        await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await waitWhile(
      () =>
          find.byType(CircularProgressIndicator).evaluate().isNotEmpty ||
          find.text('Adjust picture').evaluate().isEmpty,
    );
    expect(find.text('Adjust picture'), findsOneWidget);
    // The page finishes sliding in
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byIcon(Icons.check));
    await waitWhile(() => result == null);
    expect(result, isNotNull);
    return img.decodeImage(result!)!;
  }

  testWidgets('a profile picture is cropped square', (tester) async {
    final picture = await cropAndSave(
      tester,
      photo(png: false),
      PictureCrop.avatar,
    );
    expect(picture.width, picture.height);
    expect(picture.height, 200);
  });

  testWidgets('a background is cropped to the screen', (tester) async {
    final picture = await cropAndSave(
      tester,
      photo(png: true),
      PictureCrop.background,
    );
    expect(picture.width / picture.height, closeTo(1080 / 2340, 0.02));
    expect(picture.height, 200);
  });
}
