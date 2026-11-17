// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// A chat's notification on an Android phone, from pushes that come through
// Firebase as Sygnal sends them (utils/test_server.dart, asFirebaseDelivers),
// shown by the push helper (lib/utils/push_helper.dart). The phone's
// notification shade is a stand-in (utils/notification_shade.dart); how
// Android draws the notification can only be seen on a phone.
//
// Reported for 1.1.39: a chat's notification only showed its newest
// message, and stayed after the chat was read in the app. A Firebase push
// doesn't say which of the app's accounts it is for, and the push helper
// then showed it under another id than the one it looks for when it adds a
// message, and the one the app clears.

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

import 'reading_test.dart' show openChat;
import 'utils/notification_shade.dart';
import 'utils/test_server.dart';

void main() {
  group('A chat notification', skip: skipWithoutTestServer, () {
    late Client alice;
    late Client carol;
    late TestGroup group;
    late String pushkey;
    late L10n l10n;
    late NotificationShade shade;
    Room channel(Client client, String name) =>
        client.getRoomById(group.channels[name]!)!;

    /// Alice writes [text] in [name], and the push reaches carol's phone.
    Future<void> aliceWrites(String name, String text) async {
      final eventId = await channel(alice, name).sendTextEvent(text);
      final push = await waitForPush(pushkey, eventId!);
      await pushHelper(
        PushNotification.fromJson(asFirebaseDelivers(push)),
        clients: [carol],
        l10n: l10n,
        flutterLocalNotificationsPlugin: FlutterLocalNotificationsPlugin(),
      );
    }

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      l10n = await lookupL10n(const Locale('nb'));
      shade = NotificationShade.install();
      alice = await logIn('alice');
      carol = await logIn('carol');
      group = await newGroup(alice, [carol], channels: ['general', 'spill']);
      pushkey = await addPusher(carol);
    });
    setUp(() => shade.cancelAll());
    tearDownAll(logOutEveryone);

    test('shows every new message, not only the last', () async {
      await aliceWrites('general', 'Hei!');
      await aliceWrites('general', 'Kommer du i kveld?');
      await aliceWrites('general', 'Ta med kortstokken');

      expect(shade.notifications, hasLength(1));
      final id = chatNotificationId(carol, group.channels['general']!);
      expect(shade.messages[id]?.messages?.map((m) => m.text), [
        'Hei!',
        'Kommer du i kveld?',
        'Ta med kortstokken',
      ]);
    });

    test('goes when the chat is read in the app', () async {
      await aliceWrites('spill', 'Pizza?');
      await aliceWrites('spill', 'Eller taco?');
      final room = channel(carol, 'spill');
      final id = chatNotificationId(carol, room.id);
      expect(shade.notifications.keys, contains(id));

      await eventually(
        'carol gets the messages',
        () => textOfLast(room) == 'Eller taco?',
      );
      await openChat(room, l10n);
      expect(shade.notifications.keys, isNot(contains(id)));
    });

    // Reported for 1.1.39 too: "Mark as read" in a group's channel list
    // marked the channel unread instead, and in the chat list it only took
    // the mark away, so the messages and the notification stayed unread.
    test('goes when the chat is marked read in the list', () async {
      final room = channel(carol, 'general');
      await aliceWrites('general', 'Middag kl 18');
      await aliceWrites('general', 'Svar når du ser dette');
      final id = chatNotificationId(carol, room.id);
      expect(shade.notifications.keys, contains(id));
      await eventually(
        'carol gets the messages',
        () => textOfLast(room) == 'Svar når du ser dette' && room.isUnread,
      );

      // She marks the channel read from the list, without opening it
      expect(offersMarkRead(room), isTrue, reason: 'the menu says read');
      await markChatRead(room, l10n: l10n);
      expect(shade.notifications.keys, isNot(contains(id)));
      await eventually(
        'the server counts nothing unread for carol',
        () =>
            !room.isUnread &&
            room.notificationCount == 0 &&
            !room.hasNewMessages,
      );
      expect(offersMarkRead(room), isFalse);
    });

    test('marked unread is no longer unread once marked read', () async {
      final room = channel(carol, 'spill');
      await room.markUnread(true);
      await eventually('carol sees the chat unread', () => room.isUnread);
      expect(offersMarkRead(room), isTrue);

      await markChatRead(room, l10n: l10n);
      await eventually('carol sees the chat read', () => !room.isUnread);
    });
  });
}

String? textOfLast(Room room) {
  final last = room.lastEvent;
  return last == null ? null : textOf(last);
}
