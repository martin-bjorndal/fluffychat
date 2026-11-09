// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Picking pictures and videos in the browser the way Safari on iPhone does
// it (pickWebFiles in lib/gruppechat/web_files_browser.dart). Runs in a
// browser:
//   flutter test --platform chrome test/gruppechat/web_picker_test.dart

@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:file_picker/file_picker.dart';
import 'package:fluffychat/gruppechat/web_files.dart';
import 'package:flutter_test/flutter_test.dart';

@JS('eval')
external JSAny? _run(String script);

bool _js(String script) => (_run(script) as JSBoolean).toDart;

String _jsString(String script) => (_run(script) as JSString).toDart;

void main() {
  // The browser opens no picker in a test; keep the input it would fill
  setUp(
    () => _run('''
      window.pickerInput = null;
      HTMLInputElement.prototype.click = function () { window.pickerInput = this; };
    '''),
  );

  // Puts files on the input, as the picker does, without telling anyone
  void choose(Map<String, String> files) => _run('''
    const transfer = new DataTransfer();
    for (const [name, type] of ${_jsonOf(files)}) {
      transfer.items.add(new File([new Uint8Array(1000)], name, {type}));
    }
    window.pickerInput.files = transfer.files;
  ''');

  void change() =>
      _run('window.pickerInput.dispatchEvent(new Event("change"))');

  Future<void> pickerOpens() async {
    // Let the picker reach input.click()
    for (var i = 0; i < 5 && _js('window.pickerInput == null'); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(_js('window.pickerInput != null'), isTrue);
  }

  test('the input stays on the page while the picker is open', () async {
    final picked = pickWebFiles(type: FileType.media, allowMultiple: true);
    await pickerOpens();
    // Safari doesn't always tell a file input that is off the page
    expect(_js('window.pickerInput.isConnected'), isTrue);
    choose({'photo.jpg': 'image/jpeg'});
    change();
    expect((await picked)!.single.name, 'photo.jpg');
    expect(_js('window.pickerInput.isConnected'), isFalse);
  });

  test('pictures and videos can be picked together', () async {
    final picked = pickWebFiles(type: FileType.media, allowMultiple: true);
    await pickerOpens();
    expect(_jsString('window.pickerInput.accept'), 'image/*,video/*');
    expect(_js('window.pickerInput.multiple'), isTrue);
    choose({'photo.jpg': 'image/jpeg', 'video.mov': 'video/quicktime'});
    change();
    final files = (await picked)!;
    expect(files.map((f) => f.name), ['photo.jpg', 'video.mov']);
    expect(files.map((f) => f.mimeType), ['image/jpeg', 'video/quicktime']);
    expect((await files.first.readAsBytes()).length, 1000);
  });

  test('files that arrive without a change event are picked up', () async {
    final picked = pickWebFiles(type: FileType.media, allowMultiple: true);
    await pickerOpens();
    _run('window.dispatchEvent(new Event("focus"))');
    choose({'video.mov': 'video/quicktime'});
    final files = await picked.timeout(const Duration(seconds: 5));
    expect(files!.single.name, 'video.mov');
  });

  test(
    'a video Safari prepares after the page has its focus back arrives',
    () async {
      final picked = pickWebFiles(type: FileType.media, allowMultiple: true);
      await pickerOpens();
      // The photo library closes
      _run('window.dispatchEvent(new Event("focus"))');
      // Safari prepares the video
      await Future<void>.delayed(const Duration(seconds: 1));
      choose({'video.mp4': 'video/mp4'});
      change();
      expect((await picked)!.single.name, 'video.mp4');
    },
  );

  test('closing the picker picks nothing', () async {
    final picked = pickWebFiles(type: FileType.image);
    await pickerOpens();
    expect(_jsString('window.pickerInput.accept'), 'image/*');
    expect(_js('window.pickerInput.multiple'), isFalse);
    _run('window.pickerInput.dispatchEvent(new Event("cancel"))');
    expect(await picked.timeout(const Duration(seconds: 5)), isEmpty);
    expect(_js('window.pickerInput.isConnected'), isFalse);
  });
}

String _jsonOf(Map<String, String> files) =>
    '[${files.entries.map((e) => '["${e.key}", "${e.value}"]').join(', ')}]';
