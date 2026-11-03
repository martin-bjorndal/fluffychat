// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

import 'package:matrix/matrix.dart';

/// A GIF from Giphy, with its addresses on our server.
class GiphyGif {
  final String id;
  final String title;

  /// A small moving version for the picker.
  final Uri preview;

  /// The version to send: smaller than the original, still moving.
  final Uri full;
  final int? width;
  final int? height;

  const GiphyGif({
    required this.id,
    required this.title,
    required this.preview,
    required this.full,
    this.width,
    this.height,
  });
}

/// GIF search through Giphy. The app only talks to our server, which checks
/// the access token, adds the API key and forwards to Giphy (see
/// deploy/Caddyfile), so Giphy never sees who searches.
class Giphy {
  final Client client;

  const Giphy(this.client);

  static const int _limit = 30;

  Future<List<GiphyGif>> trending({String? language}) =>
      _get('trending', {'lang': ?language});

  Future<List<GiphyGif>> search(String query, {String? language}) =>
      _get('search', {'q': query, 'lang': ?language});

  Map<String, String> get _headers => {
    'authorization': 'Bearer ${client.accessToken}',
  };

  Future<List<GiphyGif>> _get(
    String endpoint,
    Map<String, String> query,
  ) async {
    final homeserver = client.homeserver;
    if (homeserver == null) throw Exception('Not logged in');
    final uri = homeserver.resolveUri(
      Uri(
        path: '/gifs/api/v1/gifs/$endpoint',
        queryParameters: {...query, 'limit': '$_limit', 'rating': 'pg-13'},
      ),
    );
    final response = await client.httpClient.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('GIF search answered ${response.statusCode}');
    }
    return parseGiphyGifs(
      jsonDecode(utf8.decode(response.bodyBytes)),
      homeserver,
    );
  }

  /// Downloads a GIF through our server.
  Future<Uint8List> download(Uri uri) async {
    final response = await client.httpClient.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('Downloading the GIF answered ${response.statusCode}');
    }
    return response.bodyBytes;
  }
}

/// The GIFs in a Giphy search or trending answer, with their pictures'
/// addresses moved to [homeserver]. GIFs without usable pictures are left
/// out.
List<GiphyGif> parseGiphyGifs(Object? json, Uri homeserver) {
  if (json is! Map) return const [];
  final data = json['data'];
  if (data is! List) return const [];
  return [for (final item in data.whereType<Map>()) ?_parse(item, homeserver)];
}

GiphyGif? _parse(Map item, Uri homeserver) {
  final images = item['images'];
  if (images is! Map) return null;
  Map? image(String name) => images[name] is Map ? images[name] as Map : null;
  final previewImage = image('fixed_width_small') ?? image('fixed_width');
  final fullImage = image('downsized') ?? image('original');
  final preview = giphyMediaOnServer(previewImage?['url'], homeserver);
  final full = giphyMediaOnServer(fullImage?['url'], homeserver);
  final id = item['id'];
  if (preview == null || full == null || id is! String) return null;
  final title = item['title'];
  return GiphyGif(
    id: id,
    title: title is String ? title.trim() : '',
    preview: preview,
    full: full,
    width: int.tryParse('${fullImage?['width']}'),
    height: int.tryParse('${fullImage?['height']}'),
  );
}

/// Where our server serves a picture from Giphy's media servers
/// (`media.giphy.com`, `media2.giphy.com` and so on), or null for any other
/// address.
Uri? giphyMediaOnServer(Object? url, Uri homeserver) {
  if (url is! String) return null;
  final uri = Uri.tryParse(url);
  if (uri == null ||
      uri.scheme != 'https' ||
      !RegExp(r'^media\d*\.giphy\.com$').hasMatch(uri.host) ||
      !uri.path.startsWith('/media/')) {
    return null;
  }
  return homeserver.resolveUri(
    Uri(path: '/gifs${uri.path}', query: uri.hasQuery ? uri.query : null),
  );
}
