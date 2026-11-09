// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// How the app picks files in the browser ([pickWebFiles]).
library;

export 'web_files_stub.dart'
    if (dart.library.js_interop) 'web_files_browser.dart';
