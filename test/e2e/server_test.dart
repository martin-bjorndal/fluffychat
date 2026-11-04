// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// What the app gets from our server besides chats, through Caddy and the
// server's Caddyfile: GIF search, the update banner's version.json, the
// server info in settings, the call service, and the paths that must stay
// closed.

@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';

import 'package:fluffychat/gruppechat/giphy.dart';
import 'package:fluffychat/gruppechat/server_info.dart';
import 'package:fluffychat/gruppechat/update_check.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'utils/test_server.dart';

void main() {
  final skipWithoutCaddy =
      skipWithoutTestServer ??
      (testServer.behindCaddy ? null : 'Needs Caddy in front of the server');

  group('Server', skip: skipWithoutTestServer, () {
    late Client alice;

    setUpAll(() async => alice = await logIn('alice'));
    tearDownAll(logOutEveryone);

    test('the settings show the server and its upload limit', () async {
      final info = await GruppechatServerInfo.fetch(alice);
      expect(info.matrixVersion, startsWith('v1.'));
      // max_upload_size in deploy/scripts/configure-synapse.py
      expect(info.maxUploadSize, 100 * 1024 * 1024);
    });
  });

  group('Through Caddy', skip: skipWithoutCaddy, () {
    late Client alice;
    late Giphy giphy;

    setUpAll(() async {
      alice = await logIn('alice');
      giphy = Giphy(alice);
    });
    tearDownAll(logOutEveryone);

    test('the update banner finds the newest release', () async {
      final published = await fetchPublishedRelease(alice);
      expect(published?.version, testServer.webVersion['version']);
      expect(
        published?.build,
        int.parse('${testServer.webVersion['build_number']}'),
      );
      expect(isNewerRelease(published, '3579'), isTrue);
    });

    test('GIF search shows trending GIFs, then what you search', () async {
      await testServer.forget('giphy');
      final trending = await giphy.trending(language: 'no');
      expect(trending.map((gif) => gif.title), [
        'Happy Dance GIF',
        'Wave Hello GIF',
        'Cat Typing GIF',
      ]);
      final found = await giphy.search('dance', language: 'no');
      expect(found.map((gif) => gif.id), ['e2eDance']);
      // The pictures come from our server, never straight from Giphy
      expect(found.single.preview.host, testServer.homeserver.host);
      expect(found.single.full.path, startsWith('/gifs/media/'));
    });

    test('Giphy gets our API key, not who is searching', () async {
      await testServer.forget('giphy');
      await giphy.search('wave', language: 'no');
      final request = (await testServer.recorded('giphy')).single;
      final query = request['query'] as Map<String, Object?>;
      expect(query['api_key'], testServer.giphyApiKey);
      expect(query['q'], 'wave');
      expect(query['lang'], 'no');
      expect(query['rating'], 'pg-13');
      final headers = (request['headers'] as Map<String, Object?>).keys;
      for (final header in [
        'authorization',
        'cookie',
        'referer',
        'x-forwarded-for',
        'x-forwarded-host',
      ]) {
        expect(headers, isNot(contains(header)));
      }
    });

    test('a chosen GIF downloads through our server', () async {
      final gif = (await giphy.search('cat')).single;
      final preview = await giphy.download(gif.preview);
      final full = await giphy.download(gif.full);
      expect(ascii.decode(preview.sublist(0, 6)), 'GIF89a');
      expect(ascii.decode(full.sublist(0, 6)), 'GIF89a');
      expect(full, isNot(preview));
    });

    test('GIF search is only for people logged in here', () async {
      final http = testServer.httpClient();
      for (final path in [
        '/gifs/api/v1/gifs/trending?limit=1',
        '/gifs/media/e2eDance/giphy.gif',
      ]) {
        final anonymous = await http.get(testServer.homeserver.resolve(path));
        expect(anonymous.statusCode, 401, reason: path);
        final madeUp = await http.get(
          testServer.homeserver.resolve(path),
          headers: {'authorization': 'Bearer not-a-real-token'},
        );
        expect(madeUp.statusCode, 401, reason: path);
      }
      // Only search and trending; the rest of Giphy's API stays closed
      final other = await http.get(
        testServer.homeserver.resolve('/gifs/api/v1/gifs/random'),
        headers: {'authorization': 'Bearer ${alice.accessToken}'},
      );
      expect(other.statusCode, 404);
    });

    test('calls find our call service', () async {
      final services = await alice.getLiveKitServiceUrls();
      expect(services, [
        testServer.homeserver.resolve('/livekit/jwt').toString(),
      ]);
    });

    test('the call service can check who someone is', () async {
      // lk-jwt-service checks the OpenID token a caller gives it here
      final token = await alice.requestOpenIdToken(alice.userID!, {});
      final response = await testServer.httpClient().get(
        testServer.homeserver.resolve(
          '/_matrix/federation/v1/openid/userinfo'
          '?access_token=${token.accessToken}',
        ),
      );
      expect(response.statusCode, 200);
      expect(jsonDecode(response.body), {'sub': alice.userID});
    });

    test('federation and the admin API stay closed', () async {
      final http = testServer.httpClient();
      final headers = {'authorization': 'Bearer ${alice.accessToken}'};
      for (final path in [
        '/_matrix/federation/v1/version',
        '/_matrix/key/v2/server',
        '/_synapse/admin/v1/server_version',
        '/_synapse/admin/v2/users/${Uri.encodeComponent(alice.userID!)}',
      ]) {
        final response = await http.get(
          testServer.homeserver.resolve(path),
          headers: headers,
        );
        expect(response.statusCode, 404, reason: path);
      }
    });
  });
}
