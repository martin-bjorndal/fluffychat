// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Picking a video in the browser, as Safari on iPhone does it: the photo
// library closes and the page gets its focus back, but the video arrives a
// moment later, once Safari has prepared it. Runs in a browser:
//   flutter test --platform chrome test/gruppechat/web_picker_test.dart

@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:file_picker/file_picker.dart';
import 'package:file_picker_web/file_picker_web.dart';
import 'package:fluffychat/gruppechat/web_files.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

@JS('eval')
external JSAny? _run(String script);

void main() {
  setUpAll(() => FilePickerWeb.registerWith(webPluginRegistrar));

  // The browser opens no picker in a test; keep the input it would fill
  setUp(
    () => _run('''
      window.pickerInput = null;
      HTMLInputElement.prototype.click = function () { window.pickerInput = this; };
    '''),
  );

  Future<List<PlatformFile>> pickSlowVideo(WebOptions options) async {
    final picked = FilePickerPlatform.instance.pickFiles(
      type: FileType.media,
      webOptions: options,
    );
    // The photo library closes
    _run('window.dispatchEvent(new Event("focus"))');
    // Safari prepares the video
    await Future<void>.delayed(const Duration(seconds: 1));
    _run('''
      const transfer = new DataTransfer();
      transfer.items.add(new File([new Uint8Array(1000)], "video.mp4", {type: "video/mp4"}));
      window.pickerInput.files = transfer.files;
      window.pickerInput.dispatchEvent(new Event("change"));
    ''');
    return picked;
  }

  test("with file_picker's defaults, the video is lost", () async {
    expect(await pickSlowVideo(const FilePickerWebOptions()), isEmpty);
  });

  test("the app's picker waits for it", () async {
    final files = await pickSlowVideo(gruppechatWebPickerOptions);
    expect(files.single.name, 'video.mp4');
  });
}
