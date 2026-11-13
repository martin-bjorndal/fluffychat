// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

import 'package:fluffychat/gruppechat/video_source.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

Uint8List starting(List<int> head) =>
    Uint8List.fromList([...head, ...List.filled(100, 1)]);

void main() {
  group('videoPlayType', () {
    test('MP4 and QuickTime are told as MP4, whatever was declared', () {
      for (final brand in ['qt  ', 'mp42', 'isom', 'M4V ', '3gp5']) {
        final bytes = starting([0, 0, 0, 0x18, ...ascii.encode('ftyp$brand')]);
        expect(videoPlayType(bytes, 'application/octet-stream'), 'video/mp4');
        expect(videoPlayType(bytes, 'video/quicktime'), 'video/mp4');
      }
    });

    test('WebM is told as WebM, and Matroska keeps its type', () {
      final ebml = starting([0x1A, 0x45, 0xDF, 0xA3]);
      expect(videoPlayType(ebml, 'application/octet-stream'), 'video/webm');
      expect(videoPlayType(ebml, 'video/x-matroska'), 'video/x-matroska');
    });

    test('unknown bytes keep a declared video type, else MP4', () {
      final unknown = starting([9, 9, 9, 9, 9, 9, 9, 9]);
      expect(videoPlayType(unknown, 'video/ogg'), 'video/ogg');
      expect(videoPlayType(unknown, ''), 'video/mp4');
      expect(videoPlayType(Uint8List(3), 'video/ogg'), 'video/ogg');
    });
  });

  test('a WebVideoSource is released once', () {
    final source = WebVideoSource(
      MatrixFile(
        bytes: starting([0, 0, 0, 0x18, ...ascii.encode('ftypmp42')]),
        name: 'v.mp4',
        mimeType: 'video/mp4',
      ),
    );
    expect(source.uri.data!.mimeType, 'video/mp4');
    expect(source.isReleased, isFalse);
    source
      ..release()
      ..release();
    expect(source.isReleased, isTrue);
  });

  testWidgets("a video the browser can't play can be downloaded instead", (
    tester,
  ) async {
    var downloads = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: VideoCannotPlayHere(onDownload: () => downloads++),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text("This video can't be played in this browser."), findsOne);
    await tester.tap(find.text('Download file'));
    expect(downloads, 1);
  });
}
