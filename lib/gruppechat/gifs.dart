// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

import 'package:matrix/matrix.dart';

const String gifMimeType = 'image/gif';

/// Whether a file is a GIF, by its MIME type or, when that is missing or
/// generic, by the "GIF87a"/"GIF89a" signature it starts with.
bool isGif(String? mimeType, Uint8List bytes) {
  if (mimeType?.toLowerCase() == gifMimeType) return true;
  if (bytes.length < 6) return false;
  final signature = String.fromCharCodes(bytes.sublist(0, 6));
  return signature == 'GIF87a' || signature == 'GIF89a';
}

/// A GIF's width and height from its header, or null if it is too short.
(int, int)? gifSize(Uint8List bytes) {
  if (bytes.length < 10) return null;
  final width = bytes[6] | bytes[7] << 8;
  final height = bytes[8] | bytes[9] << 8;
  if (width == 0 || height == 0) return null;
  return (width, height);
}

/// A GIF sent as it is, so it keeps moving. Sent as a [MatrixImageFile],
/// the SDK makes a still thumbnail for it, which the chat shows, and
/// shrinking it to save data turns it into a still picture.
class GifFile extends MatrixFile {
  final int? width;
  final int? height;

  GifFile._(Uint8List bytes, String name, (int, int)? size)
    : width = size?.$1,
      height = size?.$2,
      super(bytes: bytes, name: name, mimeType: gifMimeType);

  factory GifFile({required Uint8List bytes, required String name}) =>
      GifFile._(bytes, name, gifSize(bytes));

  @override
  String get msgType => MessageTypes.Image;

  @override
  Map<String, dynamic> get info => {
    ...super.info,
    if (width != null) 'w': width,
    if (height != null) 'h': height,
  };
}

extension GruppechatGifEvent on Event {
  /// Whether this message is a GIF, which the chat plays instead of showing
  /// a still thumbnail.
  bool get isGif => attachmentMimetype == gifMimeType;
}
