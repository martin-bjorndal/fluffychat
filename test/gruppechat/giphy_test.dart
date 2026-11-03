// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/gruppechat/giphy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final homeserver = Uri.parse('https://chat.example.invalid');

  test("Giphy's pictures are fetched through our server", () {
    expect(
      giphyMediaOnServer(
        'https://media2.giphy.com/media/v1.Y2lk/abc123/giphy.gif?cid=1&ct=g',
        homeserver,
      ).toString(),
      'https://chat.example.invalid/gifs/media/v1.Y2lk/abc123/giphy.gif'
      '?cid=1&ct=g',
    );
    expect(
      giphyMediaOnServer(
        'https://media.giphy.com/media/abc123/100w.gif',
        homeserver,
      ).toString(),
      'https://chat.example.invalid/gifs/media/abc123/100w.gif',
    );
  });

  test('other addresses are not fetched at all', () {
    for (final url in [
      'https://evil.example/media/abc/giphy.gif',
      'https://media.giphy.com.evil.example/media/abc/giphy.gif',
      'http://media.giphy.com/media/abc/giphy.gif',
      'https://media.giphy.com/other/abc.gif',
      42,
      null,
    ]) {
      expect(giphyMediaOnServer(url, homeserver), isNull, reason: '$url');
    }
  });

  test("a Giphy answer becomes GIFs, skipping ones that can't be shown", () {
    final gifs = parseGiphyGifs({
      'data': [
        {
          'type': 'gif',
          'id': 'abc123',
          'title': ' Happy Dance GIF ',
          'images': {
            'fixed_width_small': {
              'url': 'https://media1.giphy.com/media/abc123/100w.gif',
              'width': '100',
              'height': '75',
            },
            'downsized': {
              'url': 'https://media1.giphy.com/media/abc123/giphy.gif',
              'width': '480',
              'height': '360',
            },
          },
        },
        {
          'id': 'broken',
          'images': {
            'original': {'url': 'https://elsewhere.example/x.gif'},
          },
        },
      ],
      'meta': {'status': 200},
    }, homeserver);

    expect(gifs, hasLength(1));
    final gif = gifs.single;
    expect(gif.id, 'abc123');
    expect(gif.title, 'Happy Dance GIF');
    expect(
      gif.preview.toString(),
      'https://chat.example.invalid/gifs/media/abc123/100w.gif',
    );
    expect(
      gif.full.toString(),
      'https://chat.example.invalid/gifs/media/abc123/giphy.gif',
    );
    expect((gif.width, gif.height), (480, 360));
  });

  test('anything else is no GIFs', () {
    expect(parseGiphyGifs(null, homeserver), isEmpty);
    expect(parseGiphyGifs({'data': 'nope'}, homeserver), isEmpty);
  });
}
