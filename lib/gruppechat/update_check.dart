// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/gruppechat/bubbles.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:universal_html/html.dart' as html;
import 'package:url_launcher/url_launcher.dart';

/// The newest release, as the web app's version.json on our server says.
/// release/deploy-web.sh publishes it with every release.
class PublishedRelease {
  final String version;
  final int build;

  const PublishedRelease(this.version, this.build);

  /// Reads `{"version": "1.1.3", "build_number": "3570", …}`; null when
  /// either is missing.
  static PublishedRelease? fromJson(Object? json) {
    if (json is! Map) return null;
    final version = json['version'];
    final build = int.tryParse('${json['build_number']}');
    if (version is! String || build == null) return null;
    return PublishedRelease(version, build);
  }
}

/// Whether [published] is newer than the running build, [runningBuild].
bool isNewerRelease(PublishedRelease? published, String? runningBuild) {
  final running = int.tryParse(runningBuild ?? '');
  return published != null && running != null && published.build > running;
}

/// The newest release, from version.json on [client]'s server, or null when
/// the server doesn't publish one.
Future<PublishedRelease?> fetchPublishedRelease(Client client) async {
  final homeserver = client.homeserver;
  if (homeserver == null) return null;
  final response = await client.httpClient.get(
    homeserver.resolve('version.json'),
    headers: {'cache-control': 'no-cache'},
  );
  if (response.statusCode != 200) return null;
  return PublishedRelease.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
}

/// Tells people when a newer version is out: on Android with a link to
/// Google Play, in the web app with a button that reloads the page.
abstract final class GruppechatUpdateCheck {
  static AppLifecycleListener? _listener;
  static DateTime? _lastCheck;
  static int? _webBuildAtLoad;
  static int? _shownFor;

  /// Checks now, and again whenever the app comes back to the foreground,
  /// at most every 30 minutes.
  static void start(Client client) {
    _listener ??= AppLifecycleListener(onResume: () => check(client));
    check(client);
  }

  static Future<void> check(Client client) async {
    final now = DateTime.now();
    final last = _lastCheck;
    if (last != null && now.difference(last) < const Duration(minutes: 30)) {
      return;
    }
    _lastCheck = now;
    try {
      final published = await fetchPublishedRelease(client);
      if (published == null) return;
      final bool newer;
      if (kIsWeb) {
        // The page runs whatever was published when it loaded.
        final atLoad = _webBuildAtLoad ??= published.build;
        newer = published.build > atLoad;
      } else {
        final running = (await PackageInfo.fromPlatform()).buildNumber;
        newer = isNewerRelease(published, running);
      }
      // Not in a bubble: it's told when the app opens
      if (newer && _shownFor != published.build && !GruppechatBubbles.active) {
        _shownFor = published.build;
        _show(published);
      }
    } catch (e, s) {
      Logs().w('Could not check for a newer release', e, s);
    }
  }

  static void _show(PublishedRelease release) {
    final context =
        FluffyChatApp.router.routerDelegate.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    final l10n = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showMaterialBanner(
      MaterialBanner(
        content: Text(l10n.gruppechatUpdateAvailable(release.version)),
        actions: [
          TextButton(
            onPressed: messenger.hideCurrentMaterialBanner,
            child: Text(l10n.gruppechatLater),
          ),
          TextButton(
            onPressed: () {
              messenger.hideCurrentMaterialBanner();
              if (kIsWeb) {
                html.window.location.reload();
              } else {
                launchUrl(
                  Uri.parse(
                    'https://play.google.com/store/apps/details?id=${AppConfig.appId}',
                  ),
                  mode: LaunchMode.externalApplication,
                );
              }
            },
            child: Text(kIsWeb ? l10n.gruppechatReload : l10n.gruppechatUpdate),
          ),
        ],
      ),
    );
  }
}
