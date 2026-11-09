// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// When a pick in the browser is over (WebFilePick in
// lib/gruppechat/web_pick.dart), whichever events Safari sends or leaves out.

import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluffychat/gruppechat/web_pick.dart';
import 'package:flutter_test/flutter_test.dart';

/// The page's file input, as the pick sees it.
class FakeInput {
  final files = <XFile>[];

  late final pick = WebFilePick(
    selectedCount: () => files.length,
    readFiles: () async => List.of(files),
    checkEvery: const Duration(milliseconds: 20),
    giveUpAfterFocus: const Duration(milliseconds: 300),
  );

  void choose(String name) =>
      files.add(XFile.fromData(Uint8List(10), name: name, path: name));
}

Future<void> wait(int milliseconds) =>
    Future<void>.delayed(Duration(milliseconds: milliseconds));

void main() {
  test('a change event ends the pick with the files', () async {
    final input = FakeInput();
    input.choose('photo.jpg');
    input.pick.changed();
    expect((await input.pick.result).single.name, 'photo.jpg');
  });

  test('files on the input end the pick without any event', () async {
    final input = FakeInput();
    await wait(50);
    input.choose('video.mov');
    final files = await input.pick.result.timeout(const Duration(seconds: 2));
    expect(files.single.name, 'video.mov');
  });

  test('a video that comes a while after the focus still arrives', () async {
    final input = FakeInput();
    input.pick.focused();
    await wait(200);
    input.choose('video.mov');
    expect((await input.pick.result).single.name, 'video.mov');
  });

  test('a cancel event ends the pick with nothing', () async {
    final input = FakeInput();
    input.pick.cancelled();
    expect(await input.pick.result, isEmpty);
  });

  test('a cancel event with files on the input still gives them', () async {
    final input = FakeInput();
    input.choose('photo.jpg');
    input.pick.cancelled();
    expect((await input.pick.result).single.name, 'photo.jpg');
  });

  test('without a cancel event, a long focus with nothing ends it', () async {
    final input = FakeInput();
    input.pick.focused();
    final files = await input.pick.result.timeout(const Duration(seconds: 2));
    expect(files, isEmpty);
  });

  test('only the first ending counts', () async {
    final input = FakeInput();
    input.choose('photo.jpg');
    input.pick.changed();
    input.pick.cancelled();
    input.pick.changed();
    expect((await input.pick.result).single.name, 'photo.jpg');
  });

  test('a picked file keeps what Safari tells about it', () async {
    // Safari's File: name, type, size and lastModified, no lastModifiedDate
    final file = webPickedFile(
      Uint8List(1000),
      name: 'IMG_0001.jpeg',
      type: 'image/jpeg',
      size: 1000,
      lastModified: 1762650000000,
    );
    expect(file.name, 'IMG_0001.jpeg');
    expect(file.mimeType, 'image/jpeg');
    expect(await file.length(), 1000);
    expect(
      await file.lastModified(),
      DateTime.fromMillisecondsSinceEpoch(1762650000000),
    );
    expect((await file.readAsBytes()).length, 1000);
  });

  test('a file the browser gives no type gets one from its name', () {
    final file = webPickedFile(
      Uint8List(10),
      name: 'IMG_0003.HEIC',
      type: '',
      size: 10,
    );
    expect(file.mimeType, 'image/heic');
  });

  test('accept lists pictures and videos the way browsers read it', () {
    expect(webPickerAccept(FileType.media), 'image/*,video/*');
    expect(webPickerAccept(FileType.image), 'image/*');
    expect(webPickerAccept(FileType.any), '');
    expect(webPickerAccept(FileType.custom, ['txt', '.key']), '.txt,.key');
  });
}
