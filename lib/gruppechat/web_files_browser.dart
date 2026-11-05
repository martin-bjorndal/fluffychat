// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:file_picker/file_picker.dart';
import 'package:file_picker_web/file_picker_web.dart';

/// By default, file_picker counts a pick as cancelled when the page gets its
/// focus back and no file has come within half a second. Safari on iPhone
/// takes longer than that to prepare a video from the photo library, so
/// videos were lost without a word while photos worked. Here only the file
/// input's own cancel event counts.
const WebOptions gruppechatWebPickerOptions = FilePickerWebOptions(
  cancelUploadOnWindowBlur: false,
);
