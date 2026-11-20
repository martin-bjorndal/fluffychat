// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Sounds of messages in other chats while the app is open. Reported in
// 1.1.29: on a OnePlus phone, a message in a chat that wasn't open made no
// sound while the app was open, as some Android phones don't sound the
// notifications of the app on screen. Now the app plays the chat's
// notification sound itself and shows the notification without one
// (lib/gruppechat/sounds.dart, from lib/utils/push_helper.dart), at the
// volume chosen in the chat settings. The phone's notification shade and
// the app's audio are stand-ins (utils/notification_shade.dart and
// GruppechatSounds.onPlay); what it sounds like, and whether OnePlus now
// sounds, can only be checked on a phone. So can whether the phone's silent
// mode is read right: here GruppechatSounds.onPhoneQuiet stands in for it.

@Timeout(Duration(minutes: 3))
library;

import 'dart:ui' show Locale;

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/gruppechat/sounds.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/push_helper.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/notification_shade.dart';
import 'utils/test_server.dart';

void main() {
  group('A message while the app is open', skip: skipWithoutTestServer, () {
    late Client alice;
    late Client carol;
    late TestGroup group;
    late String pushkey;
    late L10n l10n;
    late NotificationShade shade;
    final played = <(String, double)>[];
    Room channel(Client client, String name) =>
        client.getRoomById(group.channels[name]!)!;

    /// alice writes [text] in [name], and the push reaches carol's running
    /// app, as the push helper gets it; [onScreen] when the app is open.
    Future<int> writes(
      String name,
      String text, {
      required bool onScreen,
    }) async {
      final eventId = await channel(alice, name).sendTextEvent(text);
      final push = await waitForPush(pushkey, eventId!);
      await pushHelper(
        PushNotification.fromJson(push['notification'] as Map<String, Object?>),
        clients: [carol],
        l10n: l10n,
        appOnScreen: onScreen,
        flutterLocalNotificationsPlugin: FlutterLocalNotificationsPlugin(),
      );
      // The sound isn't awaited: first the app asks if the phone is on silent
      await pumpEventQueue();
      return '${carol.clientName}_${group.channels[name]}'.hashCode;
    }

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      await AppSettings.init();
      l10n = await lookupL10n(const Locale('nb'));
      shade = NotificationShade.install();
      alice = await logIn('alice');
      carol = await logIn('carol');
      group = await newGroup(alice, [carol], channels: ['general', 'spill']);
      pushkey = await addPusher(carol);
      GruppechatSounds.onPlay = (asset, volume) => played.add((asset, volume));
    });
    setUp(() {
      played.clear();
      shade.notifications.clear();
      shade.channels.clear();
      GruppechatSounds.resetNotificationPause();
    });
    tearDownAll(() async {
      GruppechatSounds.onPlay = null;
      await logOutEveryone();
    });

    test('the app plays the notification sound itself', () async {
      final id = await writes('general', 'Hei Carol!', onScreen: true);
      expect(played, [('assets/sounds/notification.mp3', 1.0)]);
      // The notification is still shown, on the channel without a sound
      expect(shade.notifications[id]?.channelId, gruppechatOnScreenChannelId);
      expect(shade.notifications[id]?.body, 'Hei Carol!');
    });

    test('the chat\'s own sound, at the volume carol chose', () async {
      final room = channel(carol, 'spill');
      await gruppechatSetChatSound(room, GruppechatSound.meow);
      await eventually(
        'carol has chosen Mjau',
        () => gruppechatChatSound(room) == GruppechatSound.meow,
      );
      // She turns the app's sounds down in the chat settings
      await gruppechatSetSoundVolume(0.33);
      expect(AppSettings.gruppechatSoundVolume.value, 0.3);
      await writes('spill', 'Mjau!', onScreen: true);
      expect(played, [(GruppechatSound.meow.asset, 0.3)]);

      // And all the way down: nothing at all
      played.clear();
      GruppechatSounds.resetNotificationPause();
      await gruppechatSetSoundVolume(0);
      await writes('spill', 'Mjau?', onScreen: true);
      expect(played, isEmpty);
      await gruppechatSetSoundVolume(1);
      await gruppechatSetChatSound(room, null);
    });

    test('a burst of messages sounds once', () async {
      await writes('general', 'En', onScreen: true);
      await GruppechatSounds.notification(channel(carol, 'general'));
      await pumpEventQueue();
      expect(played, hasLength(1));
    });

    test('a chat carol has quieted in Android stays quiet', () async {
      shade.channels[AppConfig.pushNotificationsChannelId] =
          const AndroidNotificationChannel(
            AppConfig.pushNotificationsChannelId,
            'Meldinger',
            importance: Importance.low,
            playSound: false,
          );
      final id = await writes('general', 'Stille?', onScreen: true);
      expect(played, isEmpty);
      // Shown as she set it up, not on the channel for the open app
      expect(
        shade.notifications[id]?.channelId,
        AppConfig.pushNotificationsChannelId,
      );
    });

    test('so does one conversation she has quieted', () async {
      // Android keeps a conversation's own settings as a channel of its own
      final id =
          '${AppConfig.pushNotificationsChannelId} : '
          '${group.channels['spill']}';
      shade.channels[id] = AndroidNotificationChannel(
        id,
        'spill',
        importance: Importance.low,
      );
      await writes('spill', 'Psst', onScreen: true);
      expect(played, isEmpty);
      // Other chats still sound
      await writes('general', 'Hallo', onScreen: true);
      expect(played, hasLength(1));
    });

    test('no sound when carol sends a message herself', () async {
      // Reported in 1.1.40: a sound played when you sent a message yourself
      GruppechatSounds.onPhoneQuiet = () async => false;
      addTearDown(() => GruppechatSounds.onPhoneQuiet = null);
      final room = channel(carol, 'general');
      final timeline = await room.getTimeline();
      addTearDown(timeline.cancelSubscriptions);
      final openedAt = DateTime.now().subtract(const Duration(minutes: 1));
      // What the running app notifies of, with a sound (MatrixState)
      final notified = <String?>[];
      final sub = carol.onNotification.stream.listen(
        (event) => notified.add(event.eventId),
      );
      addTearDown(sub.cancel);

      // She writes in the open chat, as the chat's send button does, which
      // plays no sound of its own since 1.1.41 (lib/pages/chat/chat.dart,
      // send; the widget itself isn't run here)
      final sent = await room.sendTextEvent('Hei alle sammen!');
      await eventually(
        'carol has her message in the open chat',
        () => timeline.events.any((e) => e.eventId == sent),
      );
      final message = timeline.events.firstWhere((e) => e.eventId == sent);
      // Her own message doesn't get the sound of one coming in, nor a
      // notification
      expect(gruppechatPlaysReceivedSound(message, openedAt), isFalse);
      // alice's answer does, so the notifications are listened to
      final answer = await channel(alice, 'general').sendTextEvent('Hei!');
      await eventually(
        'carol is notified of alice\'s answer',
        () => notified.contains(answer),
      );
      expect(notified, isNot(contains(sent)));
      await pumpEventQueue();
      expect(played, isEmpty);
    });

    test('nothing sounds while carol\'s phone is on silent', () async {
      // Reported in 1.1.40: sounds in the open chat on a phone on silent
      GruppechatSounds.onPhoneQuiet = () async => true;
      addTearDown(() => GruppechatSounds.onPhoneQuiet = null);
      final room = channel(carol, 'general');
      final timeline = await room.getTimeline();
      addTearDown(timeline.cancelSubscriptions);
      final openedAt = DateTime.now().subtract(const Duration(minutes: 1));

      // A message comes in while she has the chat and the app open
      final id = await writes('general', 'Er du stille?', onScreen: true);
      expect(played, isEmpty);
      // The quiet one doesn't start the 2 seconds between notification
      // sounds: taken off silent at once, the next one sounds
      GruppechatSounds.onPhoneQuiet = () async => false;
      await GruppechatSounds.notification(room);
      expect(played, [('assets/sounds/notification.mp3', 1.0)]);
      played.clear();
      GruppechatSounds.onPhoneQuiet = () async => true;

      await eventually(
        'carol has the message in the open chat',
        () => timeline.events.any((e) => e.body == 'Er du stille?'),
      );
      final message = timeline.events.firstWhere(
        (e) => e.body == 'Er du stille?',
      );
      // The open chat would give it the sound of a message coming in
      expect(gruppechatPlaysReceivedSound(message, openedAt), isTrue);
      GruppechatSounds.received();
      await pumpEventQueue();
      expect(played, isEmpty);
      // The notification is still shown, quietly
      expect(shade.notifications[id]?.body, 'Er du stille?');

      // Off silent again, messages sound
      GruppechatSounds.onPhoneQuiet = () async => false;
      GruppechatSounds.resetNotificationPause();
      await writes('general', 'Og no?', onScreen: true);
      expect(played, [('assets/sounds/notification.mp3', 1.0)]);
    });

    test('with the app closed, the notification sounds as before', () async {
      final id = await writes('general', 'Er du der?', onScreen: false);
      expect(played, isEmpty);
      expect(
        shade.notifications[id]?.channelId,
        AppConfig.pushNotificationsChannelId,
      );
    });
  });
}
