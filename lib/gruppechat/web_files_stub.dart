// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';

/// Outside the browser, file_picker picks the files.
Future<List<XFile>?> pickWebFiles({
  FileType type = FileType.any,
  List<String>? allowedExtensions,
  bool allowMultiple = false,
}) async => null;
