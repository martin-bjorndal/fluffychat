// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

import 'package:universal_html/universal_html.dart' as web;

/// A Blob URL of type [type] for [bytes], and how to free it again.
(Uri, void Function()) videoUrl(Uint8List bytes, String type) {
  final url = web.Url.createObjectUrlFromBlob(web.Blob([bytes], type));
  return (Uri.parse(url), () => web.Url.revokeObjectUrl(url));
}
