// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

/// One opening of a video in the viewer (lib/pages/image_viewer/video_player.dart).
///
/// Closing the viewer while the video still downloads used to crash the app
/// (progress reached a closed screen) or start the video anyway, playing
/// unseen in the background. Once [close] is called, nothing more reaches
/// the viewer and no player is kept.
class VideoOpening {
  bool _closed = false;

  bool get isClosed => _closed;

  void close() => _closed = true;

  /// Downloads and decrypts [event]'s video. [onProgress] gets the share
  /// downloaded so far (null when unknown or done), only while open.
  /// Returns null when the viewer closed before the download finished.
  Future<MatrixFile?> download(
    Event event, {
    void Function(double? progress)? onProgress,
  }) async {
    final size = event.content
        .tryGetMap<String, Object?>('info')
        ?.tryGet<int>('size');
    final file = await event.downloadAndDecryptAttachment(
      onDownloadProgress: size == null || onProgress == null
          ? null
          : (bytes) {
              if (_closed) return;
              final progress = bytes / size;
              onProgress(progress < 1 ? progress : null);
            },
    );
    return _closed ? null : file;
  }

  /// Gives back [player] while the viewer is open. When it has closed in the
  /// meantime, [dispose]s the player instead, so it never starts, and
  /// returns null.
  Future<T?> keep<T>(T player, Future<void> Function(T player) dispose) async {
    if (!_closed) return player;
    await dispose(player);
    return null;
  }
}
