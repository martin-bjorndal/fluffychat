// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// The photo editor's filters and adjustments (lib/gruppechat/photo_looks.dart).

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fluffychat/gruppechat/photo_looks.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// A 2×1 picture: an orange pixel and a see-through one.
Future<ui.Image> twoPixels() {
  final pixels = Uint8List.fromList([230, 120, 20, 255, 0, 0, 0, 0]);
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    2,
    1,
    ui.PixelFormat.rgba8888,
    done.complete,
  );
  return done.future;
}

Future<List<int>> rgba(ui.Image image) async {
  final data = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  return data!.buffer.asUint8List().toList();
}

Future<List<int>> painted(
  PhotoLook look, {
  void Function(Canvas, Size)? drawOnTop,
}) async {
  final source = await twoPixels();
  final result = await paintEditedPhoto(
    source,
    look: look,
    drawOnTop: drawOnTop,
  );
  final bytes = await rgba(result);
  source.dispose();
  result.dispose();
  return bytes;
}

void main() {
  test('a neutral look leaves the photo as it is', () async {
    expect(PhotoLook.neutral.isNeutral, isTrue);
    expect(await painted(PhotoLook.neutral), [230, 120, 20, 255, 0, 0, 0, 0]);
  });

  test('black and white makes the photo grey and keeps see-through', () async {
    final pixels = await painted(
      const PhotoLook(preset: PhotoLookPreset.blackWhite),
    );
    expect((pixels[0] - pixels[1]).abs(), lessThan(2));
    expect((pixels[1] - pixels[2]).abs(), lessThan(2));
    expect(pixels[3], 255);
    expect(pixels[7], 0, reason: 'the see-through pixel stays so');
  });

  test('brightness lightens on the 0–255 scale the preview uses', () async {
    final pixels = await painted(const PhotoLook(brightness: 0.5));
    // +50 on each colour, red stops at 255
    expect(pixels.sublist(0, 4), [255, 170, 70, 255]);
  });

  test('contrast and saturation move colours the expected way', () async {
    final more = await painted(const PhotoLook(contrast: 1));
    expect(more[0], greaterThan(230));
    expect(more[2], lessThan(20));
    final grey = await painted(const PhotoLook(saturation: -1));
    expect((grey[0] - grey[2]).abs(), lessThan(2));
  });

  test('the drawing on top keeps its colour', () async {
    final pixels = await painted(
      const PhotoLook(preset: PhotoLookPreset.noir),
      drawOnTop: (canvas, size) => canvas.drawRect(
        const Rect.fromLTWH(1, 0, 1, 1),
        Paint()..color = const Color(0xFFFF0000),
      ),
    );
    expect(pixels.sublist(4), [255, 0, 0, 255]);
  });

  test('sliders stay between -1 and 1', () {
    final look = PhotoLook.neutral.copyWith(brightness: 3, contrast: -4);
    expect((look.brightness, look.contrast), (1, -1));
    // Dragged back near the middle, the photo is as it was
    expect(look.copyWith(brightness: 0.02, contrast: -0.03).brightness, 0);
    expect(
      PhotoLook.neutral.copyWith(saturation: 0.01, brightness: -0.04).isNeutral,
      isTrue,
    );
  });

  test('the dice always picks a new look, never the original', () {
    final random = Random(1);
    for (final current in PhotoLookPreset.values) {
      for (var i = 0; i < 50; i++) {
        final picked = randomPhotoLookPreset(random, current);
        expect(picked, isNot(current));
        expect(picked, isNot(PhotoLookPreset.original));
      }
    }
  });

  test('the thumbnail is small and keeps the shape', () async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawPaint(Paint()..color = const Color(0xFF336699));
    final big = await recorder.endRecording().toImage(1200, 800);
    final small = await photoLookThumbnail(big);
    expect((small.width, small.height), (160, 107));
    big.dispose();
    small.dispose();
  });

  testWidgets('the controls pick a preset, reset and roll the dice', (
    tester,
  ) async {
    final thumbnail = (await tester.runAsync(twoPixels))!;
    addTearDown(thumbnail.dispose);
    var look = PhotoLook.neutral;
    Future<void> show() => tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => PhotoLookControls(
              look: look,
              thumbnail: thumbnail,
              random: Random(2),
              onChanged: (changed) => setState(() => look = changed),
            ),
          ),
        ),
      ),
    );
    await show();
    await tester.pumpAndSettle();
    final l10n = L10n.of(tester.element(find.byType(PhotoLookControls)));

    await tester.tap(find.text(l10n.gruppechatLookSepia));
    await tester.pump();
    expect(look.preset, PhotoLookPreset.sepia);

    await tester.tap(find.byTooltip(l10n.gruppechatLookRandom));
    await tester.pump();
    expect(look.preset, isNot(PhotoLookPreset.sepia));
    expect(look.preset, isNot(PhotoLookPreset.original));

    await tester.tap(find.byTooltip(l10n.reset));
    await tester.pump();
    expect(look.isNeutral, isTrue);
  });
}
