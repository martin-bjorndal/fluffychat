// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A photo or video taken for a chat, which came back after the app had
/// ended meanwhile.
class CameraLeftover {
  final String roomId;
  final String? threadRootEventId;
  final List<XFile> files;

  const CameraLeftover({
    required this.roomId,
    required this.threadRootEventId,
    required this.files,
  });
}

/// Taking a photo or video opens the phone's camera app. On a phone short of
/// memory, Android may end Hanne Chat while it is open; when the photo is
/// taken, the app starts again from the chat list, and the photo waits in the
/// image picker (`retrieveLostData`). This remembers which chat it was for,
/// so the app can open that chat with the photo ready to send.
abstract class GruppechatCamera {
  static const _chatKey = 'gruppechat.camera_chat';

  /// A photo or video found at start, for the chat to pick up when it opens.
  static CameraLeftover? waiting;

  /// Takes a photo, or a [video], for the chat [roomId].
  static Future<XFile?> take(
    SharedPreferences store,
    String roomId, {
    String? threadRootEventId,
    bool video = false,
    ImagePicker? picker,
  }) async {
    picker ??= ImagePicker();
    await store.setString(
      _chatKey,
      jsonEncode({'room': roomId, 'thread': ?threadRootEventId}),
    );
    try {
      return video
          ? await picker.pickVideo(
              source: ImageSource.camera,
              maxDuration: const Duration(minutes: 1),
            )
          : await picker.pickImage(source: ImageSource.camera);
    } finally {
      await store.remove(_chatKey);
    }
  }

  /// The photo or video that came back if the app ended while the camera
  /// was open. Only Android ends apps this way.
  static Future<CameraLeftover?> recover(
    SharedPreferences store, {
    ImagePicker? picker,
  }) async {
    final chat = store.getString(_chatKey);
    if (chat == null || defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }
    await store.remove(_chatKey);
    final lost = await (picker ?? ImagePicker()).retrieveLostData();
    final files = lost.files ?? [?lost.file];
    if (lost.isEmpty || files.isEmpty) return null;
    final json = jsonDecode(chat) as Map<String, Object?>;
    return CameraLeftover(
      roomId: json['room'] as String,
      threadRootEventId: json['thread'] as String?,
      files: files,
    );
  }

  /// The photo or video waiting for the chat [roomId], once.
  static CameraLeftover? takeWaiting(String roomId) {
    final leftover = waiting;
    if (leftover?.roomId != roomId) return null;
    waiting = null;
    return leftover;
  }
}
