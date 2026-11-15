// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/gruppechat/web_notify.dart';
import 'package:matrix/matrix.dart';
import 'package:universal_html/universal_html.dart' as web;

final _notifier = WebNotifier(
  permission: () =>
      web.Notification.supported ? web.Notification.permission : null,
  requestPermission: web.Notification.requestPermission,
  showViaWorker: (notification) async {
    final registration = await (_registration ??= _register());
    try {
      if (registration == null) {
        throw UnsupportedError('No notification service worker');
      }
      await registration.showNotification(
        notification.title,
        notification.options,
      );
    } catch (_) {
      // Gone, or never there: registered again next time, but not every
      // time, as registering can wait 10 s for the worker
      final now = DateTime.now();
      if (now.difference(_failedAt ?? DateTime(0)).inMinutes >= 5) {
        _registration = null;
        _failedAt = now;
      }
      rethrow;
    }
  },
  showViaConstructor: (notification) => web.Notification(
    notification.title,
    body: notification.body,
    icon: notification.icon,
    tag: notification.tag,
  ),
);

Future<web.ServiceWorkerRegistration?>? _registration;
DateTime? _failedAt;
var _setUp = false;

/// Registers web/notification_sw.js under a scope of its own, so it controls
/// no page and Flutter's flutter_service_worker.js at the root scope can't
/// replace it, and waits for it to be active.
Future<web.ServiceWorkerRegistration?> _register() async {
  try {
    final container = web.window.navigator.serviceWorker;
    if (container == null) return null;
    final registration = await container.register('notification_sw.js', {
      'scope': 'notification_sw/',
    });
    // Not `container.ready`: that waits for a worker controlling the page
    for (var i = 0; registration.active == null && i < 100; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    return registration.active == null ? null : registration;
  } catch (e) {
    Logs().w('Unable to register the notification service worker', e);
    return null;
  }
}

/// Shows a notification: through the service worker, which is the only way
/// on an iPhone, or with `new Notification()`.
Future<void> showWebNotification(WebNotification notification) =>
    _notifier.show(notification);

/// Sets notifications up once for the app: the service worker, a tap on a
/// notification opening its chat ([open] gets the notification's payload),
/// and asking for permission now (desktop browsers) and on the first tap
/// (Safari asks only then).
void setUpWebNotifications({
  required Future<void> Function(String payload) open,
}) {
  if (_setUp) return;
  _setUp = true;
  _notifier.askNow();
  _registration ??= _register();

  web.window.navigator.serviceWorker?.onMessage.listen((event) {
    final payload = openedWebNotification(event.data);
    if (payload == null) return;
    open(payload).catchError((Object e) {
      Logs().w('Unable to open the chat of a web notification', e);
    });
  });

  // Capture phase, so Flutter's own handling can't keep the tap from us
  const events = ['touchend', 'click'];
  late final web.EventListener onTap;
  // The first tap asks, so it is the only one listened to
  onTap = (_) {
    _notifier.askOnGesture();
    for (final type in events) {
      web.document.removeEventListener(type, onTap, true);
    }
  };
  if (_notifier.waitsForGesture) {
    for (final type in events) {
      web.document.addEventListener(type, onTap, true);
    }
  }
}
