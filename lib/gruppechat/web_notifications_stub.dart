// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/gruppechat/web_notify.dart';

/// Outside the browser, flutter_local_notifications shows notifications.
Future<void> showWebNotification(WebNotification notification) async {}

void setUpWebNotifications({
  required Future<void> Function(String payload) open,
}) {}
