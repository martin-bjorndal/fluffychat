// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// How big a photo or sticker is shown in the chat
// (lib/gruppechat/image_size.dart).

import 'package:fluffychat/gruppechat/image_size.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../utils/test_client.dart';

void main() {
  late Room room;

  setUpAll(() async {
    final client = await prepareTestClient(loggedIn: true);
    room = Room(id: '!chat:example.invalid', client: client);
  });

  Event event(
    String msgtype, {
    int? w,
    int? h,
    String type = EventTypes.Message,
  }) => Event(
    type: type,
    content: {
      'msgtype': msgtype,
      'body': 'x',
      if (w != null && h != null) 'info': {'w': w, 'h': h},
    },
    eventId: '\$1',
    senderId: '@alice:example.invalid',
    originServerTs: DateTime(2026),
    room: room,
  );

  test('portrait and landscape photos are equally wide', () {
    final wide = imageBubbleSize(event(MessageTypes.Image, w: 400, h: 200));
    final tall = imageBubbleSize(event(MessageTypes.Image, w: 200, h: 400));
    expect(wide.width, photoWidth);
    expect(wide.height, photoWidth / 2);
    expect(tall.width, photoWidth);
    expect(tall.height, photoMaxHeight);
    expect(tall.fit, BoxFit.cover);
  });

  test('a photo without a usable size is a square', () {
    for (final e in [
      event(MessageTypes.Image),
      event(MessageTypes.Image, w: 0, h: 0),
    ]) {
      final size = imageBubbleSize(e);
      expect((size.width, size.height), (photoWidth, photoWidth));
    }
  });

  test('a panorama stays whole, at least 32 high', () {
    final size = imageBubbleSize(event(MessageTypes.Image, w: 10000, h: 500));
    expect((size.width, size.height), (photoWidth, 32.0));
    expect(size.fit, BoxFit.contain);
  });

  test('sizes written as decimals count too', () {
    final e = event(MessageTypes.Image)
      ..content['info'] = {'w': 1080.0, 'h': 1440.0};
    final size = imageBubbleSize(e);
    expect(size.width, photoWidth);
    expect(size.height, closeTo(photoWidth * 4 / 3, 0.01));
  });

  test('stickers stay small and whole', () {
    final size = imageBubbleSize(
      event(MessageTypes.Sticker, w: 100, h: 200, type: EventTypes.Sticker),
    );
    expect((size.width, size.height), (64.0, 128.0));
    expect(size.fit, BoxFit.contain);
  });
}
