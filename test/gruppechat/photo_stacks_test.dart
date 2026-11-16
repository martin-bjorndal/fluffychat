// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Photos sent together lie in one stack in the chat, the first on top, and
// the arrow keys page through photos in the viewer. How the stack looks on
// a phone can only be judged there.

import 'package:fluffychat/gruppechat/file_series.dart';
import 'package:fluffychat/gruppechat/photo_stacks.dart';
import 'package:fluffychat/gruppechat/viewer_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/image_viewer/image_viewer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
// ignore: implementation_imports
import 'package:matrix/src/models/timeline_chunk.dart';

import '../utils/test_client.dart';

void main() {
  late Client client;
  late Room room;
  setUpAll(() async {
    client = await prepareTestClient();
    room = Room(id: '!r:test', client: client);
  });

  var n = 0;
  Event photo(
    String name, {
    String sender = '@alice:test',
    String? series,
    int index = 0,
    int count = 3,
    EventStatus status = EventStatus.synced,
    String type = MessageTypes.Image,
  }) => Event(
    type: EventTypes.Message,
    content: {
      'msgtype': type,
      'body': name,
      if (series != null)
        gruppechatSeriesKey: {'id': series, 'index': index, 'count': count},
    },
    eventId: '\$$name',
    senderId: sender,
    originServerTs: DateTime(2026, 1, 1, 12, n++),
    status: status,
    room: room,
  );

  Event text(String name, {String sender = '@carol:test'}) =>
      photo(name, sender: sender, type: MessageTypes.Text);

  List<String> ids(List<Event> events) =>
      events.map((e) => e.eventId.substring(1)).toList();

  group('stackPhotoSeries', () {
    test('a series becomes one stack, the first photo on top', () {
      // Newest first, as the chat list has them
      final events = [
        text('after'),
        photo('p3', series: 's', index: 2),
        photo('p2', series: 's', index: 1),
        photo('p1', series: 's', index: 0),
        text('before'),
      ];
      final stacks = <String, List<Event>>{};
      final shown = stackPhotoSeries(events, stacks);
      expect(ids(shown), ['after', 'p1', 'before']);
      expect(ids(GruppechatPhotoStacks.photosOf(stacks, shown[1])), [
        'p1',
        'p2',
        'p3',
      ]);
      expect(GruppechatPhotoStacks.photosOf(stacks, shown[0]), isEmpty);
    });

    test('a message in between splits it, nothing changes order', () {
      final events = [
        photo('p3', series: 's', index: 2),
        text('carol'),
        photo('p2', series: 's', index: 1),
        photo('p1', series: 's', index: 0),
      ];
      final stacks = <String, List<Event>>{};
      final shown = stackPhotoSeries(events, stacks);
      expect(ids(shown), ['p3', 'carol', 'p1']);
      expect(GruppechatPhotoStacks.photosOf(stacks, shown[0]), isEmpty);
      expect(ids(GruppechatPhotoStacks.photosOf(stacks, shown[2])), [
        'p1',
        'p2',
      ]);
    });

    test('only sent photos of one sender and one series stack', () {
      final events = [
        photo('other', series: 's', index: 2, sender: '@bob:test'),
        photo('failed', series: 's', index: 2, status: EventStatus.error),
        photo('p2', series: 's', index: 1),
        photo('p1', series: 't', index: 0),
        photo('alone'),
        photo('video', series: 'v', index: 1, type: MessageTypes.Video),
        photo('video0', series: 'v', index: 0, type: MessageTypes.Video),
      ];
      final stacks = <String, List<Event>>{};
      expect(ids(stackPhotoSeries(events, stacks)), ids(events));
      expect(stacks, isEmpty);
    });

    test('a jump to a photo under the top one lands on its stack', () {
      final events = [
        text('newest'),
        photo('p3', series: 's', index: 2),
        photo('p2', series: 's', index: 1),
        photo('p1', series: 's', index: 0),
        text('older'),
      ];
      expect(stackedIndexOf(events, '\$newest'), 0);
      expect(stackedIndexOf(events, '\$p2'), 1);
      expect(stackedIndexOf(events, '\$p1'), 1);
      expect(stackedIndexOf(events, '\$older'), 2);
      expect(stackedIndexOf(events, '\$missing'), -1);
    });
  });

  group('GruppechatPhotoStack', () {
    testWidgets('the stack is found also when its message was changed', (
      tester,
    ) async {
      final events = [
        photo('w2', series: 'w', index: 1, count: 2),
        photo('w1', series: 'w', index: 0, count: 2),
      ];
      final stacks = <String, List<Event>>{};
      stackPhotoSeries(events, stacks);
      // What the chat shows after a changed caption: another event, with
      // the edit's id and the same series
      final edited = photo('w1edit', series: 'w', index: 0, count: 2);

      late List<Event> found;
      await tester.pumpWidget(
        GruppechatPhotoStacks(
          stacks: stacks,
          child: Builder(
            builder: (context) {
              found = GruppechatPhotoStacks.of(context, edited);
              return MaterialApp(
                home: Scaffold(
                  body: Center(
                    child: GruppechatPhotoStack(
                      photos: found,
                      width: 200,
                      height: 150,
                      child: const SizedBox(
                        key: Key('top'),
                        width: 200,
                        height: 150,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();
      expect(ids(found), ['w1', 'w2']);
      // The count shows on the top photo
      expect(find.text('2'), findsOneWidget);
      // The next photo sticks out above and to the right of the top one
      final top = tester.getRect(find.byKey(const Key('top')));
      final stackRect = tester.getRect(find.byType(GruppechatPhotoStack));
      expect(stackRect.top, lessThan(top.top));
      expect(stackRect.right, greaterThan(top.right));
    });
  });

  group('the image viewer', () {
    testWidgets('the arrow keys page through the chat\'s photos', (
      tester,
    ) async {
      // Newest first, as the timeline has them
      final photos = [
        photo('v3', series: 'v', index: 2),
        photo('v2', series: 'v', index: 1),
        photo('v1', series: 'v', index: 0),
      ];
      final timeline = Timeline(
        room: room,
        chunk: TimelineChunk(events: photos),
      );
      addTearDown(timeline.cancelSubscriptions);
      // One frame to start the page animation, then let it finish
      Future<void> turnPage() async {
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  // The message field has the keys before the viewer opens
                  const TextField(autofocus: true),
                  TextButton(
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => ImageViewer(
                        photos.last,
                        timeline: timeline,
                        outerContext: context,
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      // The translations load before the first real frame
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('open'));
      await turnPage();
      final viewer = tester.state<ImageViewerController>(
        find.byType(ImageViewer),
      );
      expect(viewer.currentEvent.eventId, '\$v1');
      Future<void> press(LogicalKeyboardKey key, String shows) async {
        await tester.sendKeyEvent(key);
        await turnPage();
        expect(viewer.currentEvent.eventId, shows);
      }

      await press(LogicalKeyboardKey.arrowRight, '\$v2');
      await press(LogicalKeyboardKey.arrowRight, '\$v3');
      // No further than the last photo
      await press(LogicalKeyboardKey.arrowRight, '\$v3');
      await press(LogicalKeyboardKey.arrowLeft, '\$v2');
    });
  });

  group('GruppechatArrowKeys', () {
    testWidgets('one press is one step, also after clicking a button', (
      tester,
    ) async {
      var previous = 0;
      var next = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: GruppechatArrowKeys(
            onPrevious: () => previous++,
            onNext: () => next++,
            child: Scaffold(
              body: TextButton(onPressed: () {}, child: const Text('Neste')),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect((previous, next), (0, 1));

      await tester.tap(find.text('Neste'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect((previous, next), (1, 2));
    });
  });
}
