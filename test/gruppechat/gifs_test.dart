// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

import 'package:fluffychat/gruppechat/gifs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

void main() {
  // The header of a 300×200 GIF: signature, then width and height as
  // little-endian 16-bit numbers
  final header = Uint8List.fromList([
    ...'GIF89a'.codeUnits,
    0x2C, 0x01, // 300
    0xC8, 0x00, // 200
    0xF7, 0x00, 0x00,
  ]);

  test('GIFs are recognised by MIME type or signature', () {
    expect(isGif('image/gif', Uint8List(0)), isTrue);
    expect(isGif('IMAGE/GIF', Uint8List(0)), isTrue);
    expect(isGif(null, header), isTrue);
    expect(isGif('application/octet-stream', header), isTrue);
    expect(
      isGif(
        'image/png',
        Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]),
      ),
      isFalse,
    );
    expect(isGif(null, Uint8List.fromList('GIF'.codeUnits)), isFalse);
  });

  test('the size comes from the header', () {
    expect(gifSize(header), (300, 200));
    expect(gifSize(Uint8List.fromList('GIF89a'.codeUnits)), isNull);
  });

  test('a GIF is sent as an image with its size and no thumbnail', () {
    final file = GifFile(bytes: header, name: 'funny.gif');
    expect(file, isNot(isA<MatrixImageFile>()));
    expect(file.msgType, MessageTypes.Image);
    expect(file.info, {
      'mimetype': 'image/gif',
      'size': header.length,
      'w': 300,
      'h': 200,
    });
  });
}
