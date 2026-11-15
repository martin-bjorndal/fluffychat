// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// How the web app shows a notification (WebNotifier in
// lib/gruppechat/web_notify.dart): on an iPhone, Safari has no
// `new Notification()`, only the service worker's showNotification.

import 'dart:convert';

import 'package:fluffychat/gruppechat/web_notify.dart';
import 'package:flutter_test/flutter_test.dart';

/// A browser as the notifier sees it.
class FakeBrowser {
  FakeBrowser({
    this.permission = 'granted',
    this.hasWorker = true,
    this.hasConstructor = true,
  });

  String permission;
  bool hasWorker;
  bool hasConstructor;
  String answer = 'granted';
  var requests = 0;
  final byWorker = <WebNotification>[];
  final byConstructor = <WebNotification>[];

  late final notifier = WebNotifier(
    permission: () => permission,
    requestPermission: () async {
      requests++;
      return permission = answer;
    },
    showViaWorker: (n) async {
      if (!hasWorker) throw UnsupportedError('no service worker');
      byWorker.add(n);
    },
    showViaConstructor: (n) {
      // Safari on iOS: "Illegal constructor"
      if (!hasConstructor) throw StateError('Illegal constructor');
      byConstructor.add(n);
    },
  );
}

const message = WebNotification(
  title: 'Familien',
  body: 'Bob: Hei!',
  tag: '!room:test',
);

void main() {
  test('an iPhone shows the notification through the service worker', () async {
    final iphone = FakeBrowser(hasConstructor: false);
    await iphone.notifier.show(message);
    expect(iphone.byWorker.single.body, 'Bob: Hei!');
    expect(iphone.byWorker.single.tag, '!room:test');
  });

  test('nothing is shown without permission', () async {
    final browser = FakeBrowser(permission: 'default');
    await browser.notifier.show(message);
    expect(browser.byWorker, isEmpty);
    expect(browser.byConstructor, isEmpty);
  });

  test('without a service worker the constructor shows it', () async {
    final browser = FakeBrowser(hasWorker: false);
    await browser.notifier.show(message);
    expect(browser.byConstructor.single.title, 'Familien');
  });

  test('a browser with neither does not throw', () async {
    final browser = FakeBrowser(hasWorker: false, hasConstructor: false);
    await browser.notifier.show(message);
    expect(browser.byWorker, isEmpty);
  });

  test('a tap asks for permission once, while not yet answered', () async {
    final browser = FakeBrowser(permission: 'default');
    final asking = browser.notifier.askOnGesture();
    // Asked inside the tap, before anything is awaited (Safari)
    expect(browser.requests, 1);
    await asking;
    await browser.notifier.askOnGesture();
    expect(browser.requests, 1);
    expect(browser.permission, 'granted');

    final refused = FakeBrowser(permission: 'denied');
    await refused.notifier.askOnGesture();
    expect(refused.requests, 0);
  });

  test('a tap on the notification opens its chat in its account', () {
    final link = webNotificationLink('Hanne Chat', '!room:test');
    expect(link, '#/rooms/!room:test?client=Hanne+Chat');
    final notification = WebNotification(
      title: 'Familien',
      body: 'Bob: Hei!',
      tag: '!room:test',
      payload: 'Hanne Chat|!room:test|\$event',
      link: link,
    );
    final data = jsonDecode(notification.options['data'] as String) as Map;
    expect(data['link'], link);

    // What web/notification_sw.js posts back to the open app
    final message = jsonEncode({'type': 'open', 'payload': data['payload']});
    expect(openedWebNotification(message), 'Hanne Chat|!room:test|\$event');
    expect(openedWebNotification('nonsense'), isNull);
    expect(openedWebNotification({'type': 'other'}), isNull);
  });
}
