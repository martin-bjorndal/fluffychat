// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

/// Outside the browser (tests), a data: URL with nothing to free.
(Uri, void Function()) videoUrl(Uint8List bytes, String type) =>
    (Uri.dataFromBytes(bytes, mimeType: type), () {});
