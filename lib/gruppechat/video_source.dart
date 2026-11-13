// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:video_player/video_player.dart';

import 'video_url_stub.dart'
    if (dart.library.js_interop) 'video_url_browser.dart';

/// The type the browser is told for a video's [bytes], from the file itself.
///
/// Safari refuses a video whose type it doesn't take, although the bytes
/// are ordinary MP4 or QuickTime, so the type another app [declared] counts
/// only when the bytes say nothing. MP4 and QuickTime (both start with an
/// `ftyp` box) are told as `video/mp4`, which every browser takes for both.
/// WebM and Matroska share a header, so a declared video type stays there.
String videoPlayType(Uint8List bytes, String declared) {
  if (bytes.length >= 8 &&
      ascii.decode(bytes.sublist(4, 8), allowInvalid: true) == 'ftyp') {
    return 'video/mp4';
  }
  final isVideoType = declared.toLowerCase().startsWith('video/');
  if (!isVideoType &&
      bytes.length >= 4 &&
      bytes[0] == 0x1A &&
      bytes[1] == 0x45 &&
      bytes[2] == 0xDF &&
      bytes[3] == 0xA3) {
    return 'video/webm';
  }
  return isVideoType ? declared : 'video/mp4';
}

/// Shown in the web app's video viewer instead of the video when the
/// browser can't play it (a format or codec it doesn't have), so the video
/// can still be had as a file.
class VideoCannotPlayHere extends StatelessWidget {
  final VoidCallback onDownload;

  const VideoCannotPlayHere({required this.onDownload, super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.gruppechatVideoCannotPlayHere,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onDownload,
              icon: const Icon(Icons.download_outlined),
              label: Text(l10n.downloadFile),
            ),
          ],
        ),
      ),
    );
  }
}

/// Where the web app's video viewer (lib/pages/image_viewer/video_player.dart)
/// plays a downloaded [MatrixFile] from.
///
/// In the browser this is a Blob URL: Safari on the iPhone wouldn't play
/// larger videos from the data: URL the viewer used before. The Blob holds a
/// copy of the video until [release], which must run once the player is gone,
/// whichever way it goes.
class WebVideoSource {
  final Uri uri;
  final void Function() _release;
  bool _released = false;

  WebVideoSource._(this.uri, this._release);

  factory WebVideoSource(MatrixFile video) {
    final (uri, release) = videoUrl(
      video.bytes,
      videoPlayType(video.bytes, video.mimeType),
    );
    return WebVideoSource._(uri, release);
  }

  bool get isReleased => _released;

  void release() {
    if (_released) return;
    _released = true;
    _release();
  }
}

/// Disposes [controller], then frees the Blob URL of [source] it played
/// from, also when disposing fails.
Future<void> disposeVideoPlayer(
  VideoPlayerController? controller,
  WebVideoSource? source,
) async {
  try {
    await controller?.dispose();
  } finally {
    source?.release();
  }
}
