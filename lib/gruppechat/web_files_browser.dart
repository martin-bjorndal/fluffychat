// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluffychat/gruppechat/web_pick.dart';
import 'package:universal_html/universal_html.dart' as web;

/// Picks files in the browser with a file input that stays on the page until
/// the pick is over ([WebFilePick] says why), instead of file_picker's.
Future<List<XFile>?> pickWebFiles({
  FileType type = FileType.any,
  List<String>? allowedExtensions,
  bool allowMultiple = false,
}) async {
  final input = web.FileUploadInputElement()
    ..multiple = allowMultiple
    ..accept = webPickerAccept(type, allowedExtensions)
    ..style.display = 'none';

  final pick = WebFilePick(
    selectedCount: () => input.files?.length ?? 0,
    readFiles: () => Future.wait(input.files!.map(_readFile)),
  );
  final subscriptions = [
    input.onChange.listen((_) => pick.changed()),
    input.on['cancel'].listen((_) => pick.cancelled()),
    web.window.onFocus.listen((_) => pick.focused()),
  ];

  web.document.body!.append(input);
  try {
    input.click();
    return await pick.result;
  } finally {
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
    input.remove();
  }
}

Future<XFile> _readFile(web.File file) async {
  final reader = web.FileReader();
  final done = reader.onLoadEnd.first;
  reader.readAsArrayBuffer(file);
  await done;
  final result = reader.result;
  if (result is! Uint8List) {
    throw Exception('Could not read ${file.name}: ${reader.error}');
  }
  return webPickedFile(
    result,
    name: file.name,
    type: file.type,
    size: file.size,
    lastModified: file.lastModified,
  );
}
