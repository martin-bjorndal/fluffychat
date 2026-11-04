// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// A picture whose caption was changed is shown as the edit, which has an ID
// of its own (Event.getDisplayEvent); the picture must load again for it.

import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../utils/test_client.dart';

void main() {
  late Client client;
  setUpAll(() async {
    client = await prepareTestClient();
    FakeMatrixApi
            .currentApi!
            .api['GET']!['/client/v1/media/download/example.org/abcd1234ascii'] =
        (_) => img.encodePng(img.Image(width: 4, height: 3));
  });

  testWidgets('a picture with a changed caption still shows', (tester) async {
    final room = Room(id: '!chat:example.invalid', client: client);
    Event picture(String eventId, String caption) => Event(
      eventId: eventId,
      senderId: '@alice:example.invalid',
      type: EventTypes.Message,
      room: room,
      originServerTs: DateTime.now(),
      content: {
        'msgtype': MessageTypes.Image,
        'body': caption,
        'filename': 'ferie.png',
        'url': 'mxc://example.org/abcd1234ascii',
        'info': {'mimetype': 'image/png'},
      },
    );

    // As image_bubble.dart shows a picture
    Future<void> show(Event event) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MxcImage(
            event: event,
            cacheKey: event.eventId,
            cacheName: room.id,
            isThumbnail: false,
            width: 100,
            height: 75,
          ),
        ),
      );
      // The picture loads from the fake server and database, outside the
      // test's clock, one step at a time
      for (var i = 0; i < 20 && find.byType(Image).evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
    }

    await show(picture(r'$photo', 'Fra stranda'));
    expect(find.byType(Image), findsOneWidget);

    await show(picture(r'$edit', 'Fra stranda i Lofoten'));
    expect(find.byType(Image), findsOneWidget);
    // The picture fades in
    await tester.pump(const Duration(seconds: 1));
  });
}
