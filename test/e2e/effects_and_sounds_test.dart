// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Effects and sounds: bob sends a message with confetti, as a long press on
// the send button does (pages/chat/chat.dart), and alice's open chat plays
// it, or plays it when she opens the chat with it unread
// (lib/gruppechat/effects.dart). alice gives the chat its own notification
// sound, which her other devices use too, and only she has
// (lib/gruppechat/sounds.dart). What it looks and sounds like can only be
// checked on a phone.

@Timeout(Duration(minutes: 3))
library;

import 'package:fluffychat/gruppechat/effects.dart';
import 'package:fluffychat/gruppechat/sounds.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'utils/test_server.dart';

void main() {
  group('Effects and sounds', skip: skipWithoutTestServer, () {
    late Client alice;
    late Client bob;
    late Room aliceChat;
    late Room bobChat;
    late Timeline aliceTimeline;
    late DateTime aliceOpened;
    late Event confetti;
    late L10n l10n;

    setUpAll(() async {
      l10n = await lookupL10n(const Locale('nb'));
      alice = await logIn('alice');
      bob = await logIn('bob');
      (bobChat, aliceChat) = await directChat(bob, alice);
      // alice has the chat open
      aliceOpened = DateTime.now().subtract(const Duration(seconds: 5));
      aliceTimeline = await aliceChat.getTimeline();
    });
    tearDownAll(logOutEveryone);

    test('a message sent with confetti arrives with it', () async {
      final eventId = await gruppechatSendWithEffect(
        bobChat,
        '**Gratulerer**, ${alice.userID}!',
        GruppechatEffect.confetti,
      );
      confetti = await arrives(
        aliceTimeline,
        'the confetti message',
        (e) => e.eventId == eventId && e.type == EventTypes.Message,
      );
      expect(gruppechatEffectOf(confetti), GruppechatEffect.confetti);
      expect(confetti.body, '**Gratulerer**, ${alice.userID}!');
      expect(confetti.formattedText, contains('<strong>Gratulerer</strong>'));
      expect(confetti.content['m.mentions'], {
        'user_ids': [alice.userID],
      });
      // Like any message from someone else, it gets the sound of a message
      // coming in
      expect(gruppechatPlaysReceivedSound(confetti, aliceOpened), isTrue);
    });

    test('the open chat plays it once', () {
      final played = <String>{};
      final toPlay = gruppechatEffectToPlay(
        aliceTimeline.events,
        played: played,
        openedAt: aliceOpened,
        unreadAtOpen: 0,
      );
      expect(toPlay?.eventId, confetti.eventId);
      played.add(toPlay!.eventId);
      expect(
        gruppechatEffectToPlay(
          aliceTimeline.events,
          played: played,
          openedAt: aliceOpened,
          unreadAtOpen: 0,
        ),
        isNull,
      );
    });

    test('opening the chat later plays it only while it is unread', () {
      final later = DateTime.now().add(const Duration(minutes: 1));
      expect(
        gruppechatEffectToPlay(
          aliceTimeline.events,
          played: {},
          openedAt: later,
          unreadAtOpen: 1,
        )?.eventId,
        confetti.eventId,
      );
      expect(
        gruppechatEffectToPlay(
          aliceTimeline.events,
          played: {},
          openedAt: later,
          unreadAtOpen: 0,
        ),
        isNull,
      );
      // Nor does an old message make a sound when the chat opens
      expect(gruppechatPlaysReceivedSound(confetti, later), isFalse);
    });

    test('a chat\'s own sound follows its owner to her other devices', () async {
      await gruppechatSetChatSound(aliceChat, GruppechatSound.bell);
      final otherPhone = await logIn('alice');
      final sameChat = await joined(otherPhone, aliceChat.id);
      await eventually(
        'the other phone knows the sound',
        () => gruppechatChatSound(sameChat) == GruppechatSound.bell,
      );
      final channel = gruppechatNotificationChannel(
        sameChat,
        usualId: 'usual',
        usualName: 'Meldinger',
        l10n: l10n,
      );
      expect(channel.id, 'gruppechat_sound_bell');
      expect(channel.name, 'Meldinger: Bjelle');
      expect(channel.sound, 'gc_bjelle');

      // Only alice's choice, not bob's
      expect(gruppechatChatSound(bobChat), isNull);

      await gruppechatSetChatSound(sameChat, null);
      await eventually(
        'back to the usual sound',
        () => gruppechatChatSound(aliceChat) == null,
      );
      expect(
        gruppechatNotificationChannel(
          aliceChat,
          usualId: 'usual',
          usualName: 'Meldinger',
          l10n: l10n,
        ).id,
        'usual',
      );
    });
  });
}
