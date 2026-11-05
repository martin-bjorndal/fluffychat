// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Push notifications and muted channels. Carol registers a pusher like the
// app (lib/utils/background_push.dart); Synapse pushes through Caddy's push
// route to a stand-in for the push gateway, and her app fetches each pushed
// message and decides whether to show it, as the push helper does
// (lib/utils/push_helper.dart). A channel muted to mentions only still
// pushes encrypted messages through a wake rule
// (lib/gruppechat/channel_mute.dart), so @role mentions get through.

@Timeout(Duration(minutes: 3))
library;

import 'package:collection/collection.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/gruppechat/calls.dart';
import 'package:fluffychat/gruppechat/channel_mute.dart';
import 'package:fluffychat/gruppechat/matrix_group.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'utils/test_server.dart';

void main() {
  group('Push notifications', skip: skipWithoutTestServer, () {
    late Client alice;
    late Client bob;
    late Client carol;
    late TestGroup group;
    late String pushkey;
    Room channel(Client client, String name) =>
        client.getRoomById(group.channels[name]!)!;

    /// The pushed message, as carol's phone fetches it.
    Future<Event?> fetch(Map<String, Object?> push) =>
        carol.getEventByPushNotification(
          PushNotification.fromJson(
            push['notification'] as Map<String, Object?>,
          ),
          storeInDatabase: false,
        );

    /// What carol's phone does with a push: fetch the message and decide.
    Future<bool> notifies(Map<String, Object?> push) async {
      final event = await fetch(push);
      return event != null && gruppechatShouldNotify(event);
    }

    setUpAll(() async {
      alice = await logIn('alice');
      bob = await logIn('bob');
      carol = await logIn('carol');
      group = await newGroup(
        alice,
        [bob, carol],
        channels: ['general', 'spill'],
      );
      final roleId = await GruppechatGroup(
        alice.getRoomById(group.spaceId)!,
      ).createRole('Spillkveld');
      await GruppechatGroup(
        alice.getRoomById(group.spaceId)!,
      ).setMemberRoles(carol.userID!, {roleId});
      await eventually(
        'carol sees her role',
        () => GruppechatGroup(
          carol.getRoomById(group.spaceId)!,
        ).state.roleIdsOf(carol.userID!).isNotEmpty,
      );

      // As BackgroundPush.setupPusher, with a made-up Firebase token
      pushkey = 'e2e-firebase-token-${carol.deviceID}';
      await carol.postPusher(
        Pusher(
          pushkey: pushkey,
          appId: '${AppConfig.pushNotificationsAppId}.${carol.deviceID}',
          appDisplayName: 'Hanne Chat',
          deviceDisplayName: 'Hanne Chat',
          lang: 'en',
          data: PusherData(
            url: testServer.pushGateway,
            format: 'event_id_only',
            additionalProperties: {
              'client_name': carol.clientName,
              'data_message': true,
            },
          ),
          kind: 'http',
        ),
        append: true,
      );
    });
    tearDownAll(logOutEveryone);

    test('a message in a channel is pushed and notifies', () async {
      final eventId = await channel(alice, 'general').sendTextEvent('Hei alle');
      final push = await _waitForPush(pushkey, eventId!);
      final notification = push['notification'] as Map<String, Object?>;
      expect(notification['room_id'], group.channels['general']);
      // event_id_only: the message itself never goes through Firebase
      expect(notification['content'], isNull);
      expect(await notifies(push), isTrue);
    });

    test('muting a channel to mentions only adds a wake rule', () async {
      await channel(
        carol,
        'spill',
      ).setPushRuleState(PushRuleState.mentionsOnly);
      await eventually(
        'carol sees the channel muted',
        () => channel(carol, 'spill').isMutedGroupChannel,
      );
      final wakeRules = GruppechatWakeRules(carol);
      await wakeRules.update();
      final rules = await carol.getPushRules();
      expect(
        rules.override?.map((rule) => rule.ruleId),
        contains(wakeRuleId(group.channels['spill']!)),
      );
      await eventually(
        'carol\'s app knows the wake rule',
        () =>
            carol.globalPushRules?.override?.any(
              (rule) => rule.ruleId == wakeRuleId(group.channels['spill']!),
            ) ??
            false,
      );
    });

    test('a muted channel stays quiet for ordinary messages', () async {
      final eventId = await channel(alice, 'spill').sendTextEvent('Bare prat');
      // The wake rule still pushes it, so the app can look for mentions
      final push = await _waitForPush(pushkey, eventId!);
      expect(await notifies(push), isFalse);
    });

    test('and for calls starting in it', () async {
      final eventId = await channel(bob, 'spill').announceCall();
      final push = await _waitForPush(pushkey, eventId!);
      expect(await notifies(push), isFalse);
    });

    test('but an @role mention in it notifies', () async {
      final eventId = await channel(
        alice,
        'spill',
      ).sendTextEvent('@spillkveld i kveld?');
      final push = await _waitForPush(pushkey, eventId!);
      expect(await notifies(push), isTrue);
    });

    test('unmuting removes the wake rule', () async {
      await channel(carol, 'spill').setPushRuleState(PushRuleState.notify);
      await eventually(
        'carol sees the channel unmuted',
        () => !channel(carol, 'spill').isMutedGroupChannel,
      );
      await GruppechatWakeRules(carol).update();
      final rules = await carol.getPushRules();
      expect(
        rules.override?.map((rule) => rule.ruleId),
        isNot(contains(wakeRuleId(group.channels['spill']!))),
      );
    });

    test('a call in a direct chat rings', () async {
      final (dm, _) = await directChat(alice, carol);
      final eventId = await dm.announceCall();
      final push = await _waitForPush(pushkey, eventId!);
      final event = await fetch(push);
      expect(event?.ringsAsCall, isTrue);
      expect(await notifies(push), isTrue);
    });

    test('a call in a channel notifies, whoever starts it', () async {
      for (final caller in [alice, bob]) {
        final eventId = await channel(caller, 'general').announceCall();
        final push = await _waitForPush(pushkey, eventId!);
        expect(await notifies(push), isTrue, reason: caller.userID);
      }
    });

    test('a silenced channel gets no wake rule and no pushes', () async {
      await channel(carol, 'spill').setPushRuleState(PushRuleState.dontNotify);
      await eventually(
        'carol sees the channel silenced',
        () => channel(carol, 'spill').pushRuleState == PushRuleState.dontNotify,
      );
      await GruppechatWakeRules(carol).update();
      final quietId = await channel(alice, 'spill').sendTextEvent('Stille');
      // A message elsewhere shows that pushes still flow
      final loudId = await channel(alice, 'general').sendTextEvent('Hallo');
      await _waitForPush(pushkey, loudId!);
      final pushes = await testServer.recorded('pushes');
      expect(pushes.where((push) => _eventIdOf(push) == quietId), isEmpty);
    });
  });
}

String? _eventIdOf(Map<String, Object?> push) =>
    (push['notification'] as Map<String, Object?>?)?['event_id'] as String?;

/// The push for [eventId] to the device with [pushkey], once Synapse has
/// sent it.
Future<Map<String, Object?>> _waitForPush(
  String pushkey,
  String eventId,
) async {
  final end = DateTime.now().add(const Duration(seconds: 30));
  while (true) {
    final pushes = await testServer.recorded('pushes');
    final push = pushes.firstWhereOrNull((push) {
      final devices = (push['notification'] as Map?)?['devices'] as List?;
      return _eventIdOf(push) == eventId &&
          (devices?.any((device) => (device as Map)['pushkey'] == pushkey) ??
              false);
    });
    if (push != null) return push;
    if (DateTime.now().isAfter(end)) {
      throw TestFailure('No push for $eventId reached the push gateway');
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}
