// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// A photo taken with the camera button reaches its chat even when Android
// ends the app while the camera app is open, as it does on phones short of
// memory. The image picker keeps such a photo for the app's next start.

import 'dart:async';

import 'package:fluffychat/gruppechat/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The camera, as the image picker on Android reaches it.
class FakeCamera extends ImagePickerPlatform {
  /// Whether the app is ended while the camera is open.
  bool appEnds = false;

  /// What the image picker keeps for the next start.
  LostDataResponse lost = LostDataResponse.empty();

  final photo = XFile('/cache/camera/photo.jpg');

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) {
    if (!appEnds) return Future.value(photo);
    lost = LostDataResponse(file: photo, type: RetrieveType.image);
    // The app that asked is gone, so the answer never comes
    return Completer<XFile?>().future;
  }

  @override
  Future<LostDataResponse> getLostData() async {
    final kept = lost;
    lost = LostDataResponse.empty();
    return kept;
  }
}

void main() {
  late FakeCamera camera;
  late SharedPreferences store;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    camera = FakeCamera();
    ImagePickerPlatform.instance = camera;
    SharedPreferences.setMockInitialValues({});
    store = await SharedPreferences.getInstance();
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('a photo taken as usual goes straight to the chat', () async {
    final file = await GruppechatCamera.take(store, '!chat:example.invalid');
    expect(file?.path, camera.photo.path);
    // Nothing is left for the next start
    expect(await GruppechatCamera.recover(store), isNull);
  });

  test(
    'a photo taken while Android ended the app comes back for its chat',
    () async {
      camera.appEnds = true;
      unawaited(
        GruppechatCamera.take(
          store,
          '!chat:example.invalid',
          threadRootEventId: r'$thread',
        ),
      );
      await pumpEventQueue();

      // The app starts again
      final leftover = await GruppechatCamera.recover(store);
      expect(leftover?.roomId, '!chat:example.invalid');
      expect(leftover?.threadRootEventId, r'$thread');
      expect(leftover?.files.map((f) => f.path), [camera.photo.path]);

      // The chat list opens the chat, which takes the photo once
      GruppechatCamera.waiting = leftover;
      expect(GruppechatCamera.takeWaiting('!other:example.invalid'), isNull);
      expect(GruppechatCamera.takeWaiting('!chat:example.invalid'), leftover);
      expect(GruppechatCamera.takeWaiting('!chat:example.invalid'), isNull);

      // And only once
      expect(await GruppechatCamera.recover(store), isNull);
    },
  );

  test('a cancelled photo leaves nothing behind', () async {
    camera.appEnds = true;
    unawaited(GruppechatCamera.take(store, '!chat:example.invalid'));
    await pumpEventQueue();
    camera.lost = LostDataResponse.empty();
    expect(await GruppechatCamera.recover(store), isNull);
  });
}
