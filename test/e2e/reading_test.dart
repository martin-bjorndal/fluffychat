// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Opening a chat, as the chat page does (lib/pages/chat/chat.dart, with
// lib/gruppechat/chat_reading.dart): it opens at the newest message, marks
// the chat as read, and clears the chat's notification, which carol's phone
// showed from a push as the push helper does (lib/utils/push_helper.dart).
// The phone's notification shade is a stand-in (utils/notification_shade.dart).

@Timeout(Duration(minutes: 3))
library;

import 'dart:ui' show Locale;

import 'package:fluffychat/gruppechat/chat_notifications.dart';
import 'package:fluffychat/gruppechat/chat_reading.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/push_helper.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/notification_shade.dart';
import 'utils/test_server.dart';

/// What the chat page does as it opens [room]'s chat, at the newest message
/// and not scrolled up: the banner it shows, if any, and where it puts the
/// read marker, which it then sets.
Future<(NewMessagesBanner?, String?)> openChat(Room room, L10n l10n) async {
  final line = newMessagesLineEventId(room);
  final timeline = await room.getTimeline();
  try {
    final banner = await newMessagesBanner(timeline, line, historyCount: 100);
    final target = readMarkerTarget(room, timeline, scrolledUp: false);
    if (target != null) {
      await timeline.setReadMarker(eventId: target, public: true);
    }
    await clearChatNotification(room, l10n: l10n);
    return (banner, target);
  } finally {
    timeline.cancelSubscriptions();
  }
}

void main() {
  group('Opening a chat', skip: skipWithoutTestServer, () {
    late Client alice;
    late Client bob;
    late Client carol;
    late TestGroup group;
    late String pushkey;
    late L10n l10n;
    late NotificationShade shade;
    Room channel(Client client, String name) =>
        client.getRoomById(group.channels[name]!)!;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      l10n = await lookupL10n(const Locale('nb'));
      shade = NotificationShade.install();
      alice = await logIn('alice');
      bob = await logIn('bob');
      carol = await logIn('carol');
      group = await newGroup(
        alice,
        [bob, carol],
        channels: ['general', 'spill'],
      );
      pushkey = await addPusher(carol);
    });
    tearDownAll(logOutEveryone);

    test('with many new messages marks it read straight away', () async {
      final room = channel(carol, 'general');
      // Carol has read up to bob's greeting
      final greeting = await channel(bob, 'general').sendTextEvent('Hei!');
      await eventually(
        'carol gets the greeting',
        () => room.lastEvent?.eventId == greeting,
      );
      await room.setReadMarker(greeting, mRead: greeting, public: true);
      await eventually(
        'carol has read the greeting',
        () => room.fullyRead == greeting && !room.hasNewMessages,
      );

      // Then bob writes more than fit on her screen
      for (var i = 1; i <= 12; i++) {
        await channel(bob, 'general').sendTextEvent('Melding $i');
      }
      await eventually(
        'carol gets all twelve',
        () =>
            room.lastEvent?.body == 'Melding 12' &&
            room.hasNewMessages &&
            room.notificationCount == 12,
      );

      final (banner, target) = await openChat(room, l10n);
      // The banner counts the new messages and jumps up to the first
      expect(banner?.count, 12);
      expect(banner?.eventId, greeting);
      // But she has seen the chat, so it is read
      expect(target, isNotNull, reason: 'opening the chat marks it read');
      await eventually(
        'the channel is no longer unread for carol',
        () => !room.hasNewMessages && room.notificationCount == 0,
      );
    });

    test('with a few new messages marks it read, without a banner', () async {
      final room = channel(carol, 'spill');
      await channel(bob, 'spill').sendTextEvent('Spill i kveld?');
      await eventually(
        'carol gets the question',
        () => room.lastEvent?.body == 'Spill i kveld?' && room.isUnread,
      );
      final (banner, target) = await openChat(room, l10n);
      expect(banner, isNull);
      expect(target, room.lastEvent?.eventId);
      await eventually(
        'the channel is no longer unread for carol',
        () => !room.hasNewMessages && room.notificationCount == 0,
      );
    });

    test('clears its notification, which was never tapped', () async {
      final room = channel(carol, 'general');
      final eventId = await channel(
        alice,
        'general',
      ).sendTextEvent('Er du der, Carol?');
      final push = await waitForPush(pushkey, eventId!);

      // Carol's phone shows the message, as the push helper does
      await pushHelper(
        PushNotification.fromJson(push['notification'] as Map<String, Object?>),
        clients: [carol],
        l10n: l10n,
        flutterLocalNotificationsPlugin: FlutterLocalNotificationsPlugin(),
      );
      final id = chatNotificationId(carol, room.id);
      expect(shade.notifications.keys, contains(id));
      expect(shade.notifications[id]?.body, 'Er du der, Carol?');

      // She opens the channel from the chat list instead
      await eventually(
        'carol gets the message',
        () => room.lastEvent?.eventId == eventId,
      );
      await openChat(room, l10n);
      expect(shade.notifications.keys, isNot(contains(id)));
    });

    test('leaves the notifications of other chats', () async {
      final eventId = await channel(alice, 'spill').sendTextEvent('Hallo?');
      final push = await waitForPush(pushkey, eventId!);
      await pushHelper(
        PushNotification.fromJson(push['notification'] as Map<String, Object?>),
        clients: [carol],
        l10n: l10n,
        flutterLocalNotificationsPlugin: FlutterLocalNotificationsPlugin(),
      );
      final id = chatNotificationId(carol, group.channels['spill']!);
      expect(shade.notifications.keys, contains(id));

      await openChat(channel(carol, 'general'), l10n);
      expect(shade.notifications.keys, contains(id));
    });
  });
}
