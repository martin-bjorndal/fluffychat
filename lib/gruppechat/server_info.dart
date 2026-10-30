// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// Software name and version from a `Server` header, such as
/// `Synapse/1.161.0`. Null when there is no header.
({String name, String? version})? parseServerHeader(String? header) {
  final product = header?.trim().split(' ').first ?? '';
  if (product.isEmpty) return null;
  final slash = product.indexOf('/');
  if (slash <= 0) return (name: product, version: null);
  return (
    name: product.substring(0, slash),
    version: product.substring(slash + 1),
  );
}

final RegExp _specVersion = RegExp(r'^v(\d+)\.(\d+)$');

/// The newest Matrix version in a `/versions` response, such as `v1.12`.
/// The old `r0` versions are ignored.
String? newestSpecVersion(Iterable<String> versions) {
  (int, int)? newest;
  for (final version in versions) {
    final match = _specVersion.firstMatch(version);
    if (match == null) continue;
    final parsed = (int.parse(match[1]!), int.parse(match[2]!));
    if (newest == null ||
        parsed.$1 > newest.$1 ||
        (parsed.$1 == newest.$1 && parsed.$2 > newest.$2)) {
      newest = parsed;
    }
  }
  return newest == null ? null : 'v${newest.$1}.${newest.$2}';
}

/// [bytes] for people, such as `100 MB`.
String formatFileSize(int bytes) {
  const megabyte = 1024 * 1024;
  if (bytes >= megabyte) return '${(bytes / megabyte).round()} MB';
  return '${(bytes / 1024).ceil()} KB';
}

/// What the app can learn about our server without the federation API,
/// which is off: the software and version from the `Server` header of a
/// client API response, the newest Matrix version and the upload limit.
class GruppechatServerInfo {
  final String? software;
  final String? version;
  final String? matrixVersion;
  final int? maxUploadSize;

  const GruppechatServerInfo({
    this.software,
    this.version,
    this.matrixVersion,
    this.maxUploadSize,
  });

  static Future<GruppechatServerInfo> fetch(Client client) async {
    final homeserver = client.homeserver;
    if (homeserver == null) return const GruppechatServerInfo();
    final response = await client.httpClient.get(
      homeserver.resolve('_matrix/client/versions'),
    );
    final server = parseServerHeader(response.headers['server']);
    String? matrixVersion;
    try {
      final json = jsonDecode(response.body);
      final versions = json is Map ? json['versions'] : null;
      if (versions is List) {
        matrixVersion = newestSpecVersion(versions.whereType<String>());
      }
    } on FormatException catch (e) {
      Logs().w('Unexpected /versions response', e);
    }
    int? maxUploadSize;
    try {
      maxUploadSize = (await client.getConfig()).mUploadSize;
    } catch (e) {
      Logs().w('Unable to fetch the upload limit', e);
    }
    return GruppechatServerInfo(
      software: server?.name,
      version: server?.version,
      matrixVersion: matrixVersion,
      maxUploadSize: maxUploadSize,
    );
  }
}

/// The server section of the homeserver settings page.
class GruppechatServerInfoTiles extends StatefulWidget {
  final Client client;

  const GruppechatServerInfoTiles({required this.client, super.key});

  @override
  State<GruppechatServerInfoTiles> createState() =>
      _GruppechatServerInfoTilesState();
}

class _GruppechatServerInfoTilesState extends State<GruppechatServerInfoTiles> {
  late final Future<GruppechatServerInfo> _info = GruppechatServerInfo.fetch(
    widget.client,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return FutureBuilder(
      future: _info,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const SizedBox.shrink();
        final info = snapshot.data;
        if (info == null) {
          return const Center(
            child: CircularProgressIndicator.adaptive(strokeWidth: 2),
          );
        }
        final maxUploadSize = info.maxUploadSize;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (info.software != null)
              ListTile(title: Text(l10n.name), subtitle: Text(info.software!)),
            if (info.version != null)
              ListTile(
                title: Text(l10n.version),
                subtitle: Text(info.version!),
              ),
            if (info.matrixVersion != null)
              ListTile(
                title: Text(l10n.gruppechatMatrixVersion),
                subtitle: Text(info.matrixVersion!),
              ),
            if (maxUploadSize != null)
              ListTile(
                title: Text(l10n.gruppechatMaxUploadSize),
                subtitle: Text(formatFileSize(maxUploadSize)),
              ),
          ],
        );
      },
    );
  }
}
