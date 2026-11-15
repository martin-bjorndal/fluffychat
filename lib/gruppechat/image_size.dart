// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// How wide a photo is shown in the chat. Portrait photos get the same width
/// as landscape ones, so a caption under them doesn't break into short lines.
const photoWidth = 256.0;

/// Very tall photos (screenshots) are cropped to this height in the chat; the
/// whole photo shows when it is opened.
const photoMaxHeight = photoWidth * 1.5;

const _stickerSize = 128.0;
const _minSide = 32.0;

/// The size and fit of a photo or sticker in the chat, from the width and
/// height the sender put in the event.
({double width, double height, BoxFit fit}) imageBubbleSize(Event event) {
  final info = event.content.tryGetMap<String, Object?>('info');
  final w = info?.tryGet<num>('w');
  final h = info?.tryGet<num>('h');
  final sticker = event.messageType == MessageTypes.Sticker;
  if (w == null || h == null || w <= 0 || h <= 0) {
    final size = sticker ? _stickerSize : photoWidth;
    return (
      width: size,
      height: size,
      fit: sticker ? BoxFit.contain : BoxFit.cover,
    );
  }
  if (sticker) {
    // Stickers stay whole inside a small square, as before
    final scale = _stickerSize / max(w, h);
    return (
      width: max(_minSide, w * scale),
      height: max(_minSide, h * scale),
      fit: BoxFit.contain,
    );
  }
  final height = photoWidth * h / w;
  return (
    width: photoWidth,
    height: height.clamp(_minSide, photoMaxHeight),
    // Whole, unless it is taller than photoMaxHeight. Contain also keeps a
    // photo whole when the sizes in the event don't match the thumbnail.
    fit: height > photoMaxHeight ? BoxFit.cover : BoxFit.contain,
  );
}
