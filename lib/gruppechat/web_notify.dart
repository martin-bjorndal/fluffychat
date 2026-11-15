// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:fluffychat/utils/push_helper.dart';
import 'package:matrix/matrix.dart';

/// A notification the web app shows. [tag] is the room's ID, so a newer
/// message in the same chat replaces the older notification.
class WebNotification {
  const WebNotification({
    required this.title,
    required this.body,
    this.icon,
    this.tag,
    this.payload,
    this.link,
  });

  /// A notification of [event], tagged with its room, whose tap opens its
  /// chat in its account.
  factory WebNotification.forEvent(
    Event event, {
    required String title,
    required String body,
    String? icon,
  }) {
    final clientName = event.room.client.clientName;
    final roomId = event.room.id;
    return WebNotification(
      title: title,
      body: body,
      icon: icon,
      tag: roomId,
      payload: FluffyChatPushPayload(
        clientName,
        roomId,
        event.eventId,
      ).toString(),
      link: webNotificationLink(clientName, roomId),
    );
  }

  final String title;
  final String body;
  final String? icon;
  final String? tag;

  /// What a tap opens: a `FluffyChatPushPayload` for `notificationTap` when
  /// the app is open, and [link] (from [webNotificationLink]) when it isn't.
  final String? payload;
  final String? link;

  /// The options for `showNotification`; `data` is what the service worker
  /// (web/notification_sw.js) hands back on a tap, as JSON: dart:html
  /// converts only the top level of a map for the browser.
  Map<String, Object> get options => {
    'body': body,
    'icon': ?icon,
    'tag': ?tag,
    // A newer message in the chat alerts again instead of replacing quietly
    if (tag != null) 'renotify': true,
    'data': jsonEncode({'payload': ?payload, 'link': ?link}),
  };
}

/// The app's address for a chat of an account, relative to the app's base:
/// the router reads it from the URL's fragment.
String webNotificationLink(String clientName, String roomId) =>
    '#/rooms/$roomId?client=${Uri.encodeQueryComponent(clientName)}';

/// How the web app shows notifications and asks to.
///
/// Safari on an iPhone has no `new Notification()`: a web app on the home
/// screen shows notifications only through a service worker, so the worker
/// comes first and the constructor is what's left for browsers without one.
/// Safari also ignores a permission request that isn't made inside a tap.
class WebNotifier {
  WebNotifier({
    required this.permission,
    required this.requestPermission,
    required this.showViaWorker,
    required this.showViaConstructor,
  });

  /// The browser's `Notification.permission`: granted, denied or default;
  /// null when the browser has no notifications.
  final String? Function() permission;
  final Future<String> Function() requestPermission;
  final Future<void> Function(WebNotification) showViaWorker;
  final void Function(WebNotification) showViaConstructor;

  bool _asked = false;

  /// Whether a tap still has something to ask.
  bool get waitsForGesture => !_asked && _permission() == 'default';

  /// Asks at start, as the app always did: desktop browsers allow that, and
  /// Safari, which doesn't, waits for [askOnGesture]. Never throws.
  Future<void> askNow() async {
    if (_permission() != 'default') return;
    try {
      await requestPermission();
    } catch (e) {
      Logs().d('Unable to ask for web notifications now', e);
    }
  }

  Future<void> show(WebNotification notification) async {
    if (_permission() != 'granted') return;
    try {
      await showViaWorker(notification);
      return;
    } catch (e) {
      Logs().d('Web notification through the service worker failed', e);
    }
    try {
      showViaConstructor(notification);
    } catch (e) {
      Logs().w('Unable to show a web notification', e);
    }
  }

  /// Asks for permission while it is unanswered, once. Called inside a tap:
  /// the request is made before anything is awaited, or Safari ignores it.
  Future<void> askOnGesture() async {
    if (!waitsForGesture) return;
    _asked = true;
    try {
      await requestPermission();
    } catch (e) {
      Logs().w('Unable to ask for web notifications', e);
    }
  }

  String? _permission() {
    try {
      return permission();
    } catch (_) {
      return null;
    }
  }
}

/// The payload of a tapped notification in a message from the service worker
/// (`{"type": "open", "payload": ...}` as JSON), or null.
String? openedWebNotification(Object? message) {
  try {
    final data = message is String ? jsonDecode(message) : message;
    if (data is Map && data['type'] == 'open' && data['payload'] is String) {
      return data['payload'] as String;
    }
  } on FormatException catch (_) {}
  return null;
}
