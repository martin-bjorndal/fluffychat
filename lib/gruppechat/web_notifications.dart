// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// How the web app shows notifications ([showWebNotification]) and asks to
/// ([setUpWebNotifications]); [WebNotifier] says why.
library;

export 'web_notifications_stub.dart'
    if (dart.library.js_interop) 'web_notifications_browser.dart';
export 'web_notify.dart';
