// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/gruppechat/file_series.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import '../utils/test_client.dart';

void main() {
  late Client client;
  setUpAll(() async => client = await prepareTestClient());

  group('fileSeriesContents', () {
    test('one file: only its caption, no series', () {
      expect(fileSeriesContents(client, caption: ' Hei ', count: 1), [
        {'body': 'Hei'},
      ]);
      expect(fileSeriesContents(client, caption: '  ', count: 1), [null]);
    });

    test('several files: the message once, on the first, one id', () {
      final contents = fileSeriesContents(client, caption: 'Tur', count: 3);
      expect(contents.map((c) => c!['body']), ['Tur', null, null]);
      final series = contents
          .map((c) => c![gruppechatSeriesKey]! as Map<String, Object?>)
          .toList();
      expect(series.map((s) => s['id']).toSet(), hasLength(1));
      expect(series.map((s) => s['index']), [0, 1, 2]);
      expect(series.map((s) => s['count']), [3, 3, 3]);
      // The next send is a new series
      final next = fileSeriesContents(client, caption: '', count: 2);
      expect(next.first!.containsKey('body'), isFalse);
      expect(
        (next.first![gruppechatSeriesKey]! as Map)['id'],
        isNot(series.first['id']),
      );
    });
  });

  group('Event.fileSeries', () {
    Event withSeries(Object? series) => Event(
      type: EventTypes.Message,
      content: {
        'msgtype': MessageTypes.Image,
        'body': 'a.png',
        gruppechatSeriesKey: ?series,
      },
      eventId: '\$e',
      senderId: '@alice:test',
      originServerTs: DateTime(2026),
      room: Room(id: '!r:test', client: client),
    );

    test('reads a series back', () {
      expect(withSeries({'id': 'abc', 'index': 1, 'count': 2}).fileSeries, (
        id: 'abc',
        index: 1,
        count: 2,
      ));
    });

    test('ignores a missing or broken series', () {
      for (final broken in [
        null,
        'abc',
        {'id': '', 'index': 0, 'count': 2},
        {'id': 'abc', 'index': 2, 'count': 2},
        {'id': 'abc', 'index': -1, 'count': 2},
        {'id': 'abc', 'index': 0, 'count': 1},
        {'id': 'abc', 'index': '0', 'count': 2},
      ]) {
        expect(withSeries(broken).fileSeries, isNull, reason: '$broken');
      }
    });

    test('a forwarded file leaves its series', () {
      final event = withSeries({'id': 'abc', 'index': 1, 'count': 2});
      expect(event.forwardedContent.containsKey(gruppechatSeriesKey), isFalse);
      expect(event.forwardedContent['body'], 'a.png');
      expect(event.fileSeries, isNotNull);
    });
  });

  test('fileReplyTarget: only the first file is the reply', () {
    final question = Event(
      type: EventTypes.Message,
      content: {'msgtype': MessageTypes.Text, 'body': 'Kvar er du?'},
      eventId: '\$q',
      senderId: '@bob:test',
      originServerTs: DateTime(2026),
      room: Room(id: '!r:test', client: client),
    );
    expect(fileReplyTarget(question, 0), question);
    expect(fileReplyTarget(question, 1), isNull);
    expect(fileReplyTarget(question, 2), isNull);
    expect(fileReplyTarget(null, 0), isNull);
  });
}
