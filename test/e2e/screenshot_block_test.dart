// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Blocking screenshots of a chat (lib/gruppechat/screenshot_block.dart):
// alice turns the block on from the settings of her direct chat with bob.
// It applies to bob too, leaves no trace in the chat, the chat list, his
// pushes or a downloaded conversation, and only alice can lift it, which
// the server enforces. Bob can have a block of his own as well; the chat
// stays blocked until both have turned theirs off. A block of someone who
// left stops counting, and in a group only moderators may turn one on.
//
// What the lab can't show: that Android really keeps screenshots and screen
// recordings out (FLAG_SECURE on the main window and on a chat bubble).
// Here the test checks the app's decision to ask for it.

@Timeout(Duration(minutes: 4))
library;

import 'dart:ui' show Locale;

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/gruppechat/chat_transcript.dart';
import 'package:fluffychat/gruppechat/screenshot_block.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/test_server.dart';

void main() {
  group('Blocking screenshots', skip: skipWithoutTestServer, () {
    late L10n l10n;
    late Client alice;
    late Client bob;
    late Client carol;
    late Room aliceChat;
    late Room bobChat;
    late Timeline bobTimeline;
    late String bobPushkey;
    late String hello;
    final blockEvents = <String>[];
    // Bob's chat page, as it tells the app which chat is on screen
    final bobsChatPage = Object();

    String nameOf(Room room, Client client) => room
        .unsafeGetUserFromMemoryOrFallback(client.userID!)
        .calcDisplayname();

    Future<void> setBlock(Room room, bool blocked) async =>
        blockEvents.add(await gruppechatSetScreenshotBlock(room, blocked));

    setUpAll(() async {
      // Unknown events shown too, so that a trace of the block would show
      SharedPreferences.setMockInitialValues({
        'chat.fluffy.hideUnknownEvents': false,
      });
      await AppSettings.init(loadWebConfigFile: false);
      await initializeDateFormatting();
      l10n = await lookupL10n(const Locale('nb'));
      alice = await logIn('alice');
      bob = await logIn('bob');
      carol = await logIn('carol');
      (aliceChat, bobChat) = await directChat(alice, bob);
      bobTimeline = await bobChat.getTimeline();
      bobPushkey = await addPusher(bob);
    });
    tearDownAll(() async {
      GruppechatSecureWindow.hide(bobsChatPage);
      await logOutEveryone();
    });

    test('alice blocks screenshots, for bob too, and nothing shows', () async {
      hello = (await aliceChat.sendTextEvent('Hei Bob'))!;
      final message = await arrives(
        bobTimeline,
        'the message',
        (e) => e.eventId == hello,
      );
      // Bob reads it
      await bobChat.setReadMarker(hello, mRead: hello);
      await eventually(
        'bob has read everything',
        () => bobChat.notificationCount == 0 && !bobChat.isUnread,
      );
      // Bob has the chat open
      GruppechatSecureWindow.show(bobsChatPage, bobChat);
      expect(GruppechatSecureWindow.secure, isFalse);
      expect(gruppechatCanDownloadTranscript(bobChat), isTrue);

      // In a direct chat both may turn it on
      expect(gruppechatCanSetScreenshotBlock(aliceChat), isTrue);
      expect(gruppechatCanSetScreenshotBlock(bobChat), isTrue);
      expect(gruppechatScreenshotSwitch(aliceChat, l10n).enabled, isTrue);
      await setBlock(aliceChat, true);

      await eventually(
        'bob sees the block',
        () => gruppechatScreenshotsBlocked(bobChat),
      );
      expect(gruppechatScreenshotBlockers(bobChat), [alice.userID]);
      expect(gruppechatHasOwnScreenshotBlock(aliceChat), isTrue);
      expect(gruppechatHasOwnScreenshotBlock(bobChat), isFalse);
      // The open chat goes secure as soon as the block arrives
      await eventually(
        "bob's window is kept secure",
        () => GruppechatSecureWindow.secure,
      );
      expect(gruppechatWindowSecure([bobChat]), isTrue);
      // Downloading the conversation isn't offered
      expect(gruppechatCanDownloadTranscript(bobChat), isFalse);
      expect(gruppechatCanDownloadTranscript(aliceChat), isFalse);

      // Alice can turn it off again; bob sees it is on, and why
      final aliceSwitch = gruppechatScreenshotSwitch(aliceChat, l10n);
      expect((aliceSwitch.on, aliceSwitch.enabled), (true, true));
      expect(aliceSwitch.subtitle, l10n.gruppechatBlockScreenshotsDescription);
      final bobSwitch = gruppechatScreenshotSwitch(bobChat, l10n);
      expect((bobSwitch.on, bobSwitch.enabled), (true, false));
      expect(
        bobSwitch.subtitle,
        contains(l10n.gruppechatScreenshotsBlockedBy(nameOf(bobChat, alice))),
      );

      // Nothing in his chat: the state event reached him, but shows no line
      final block = await arrives(
        bobTimeline,
        'the block',
        (e) => e.eventId == blockEvents.last,
      );
      expect(block.type, gruppechatScreenshotsType);
      expect(block.isVisibleInGui, isFalse);
      expect(
        bobTimeline.events.filterByVisibleInGui().map((e) => e.eventId),
        isNot(contains(block.eventId)),
      );
      // Nor in his chat list: the last message is still alice's, read
      expect(bobChat.lastEvent?.eventId, message.eventId);
      expect(bobChat.notificationCount, 0);
      expect(bobChat.hasNewMessages, isFalse);
      expect(bobChat.isUnread, isFalse);

      // No push either. A message after it is pushed, so the block's push
      // would have come before
      final after = (await aliceChat.sendTextEvent('Ingen skjermbilder'))!;
      await waitForPush(bobPushkey, after);
      final pushes = await testServer.recorded('pushes');
      expect(pushes.map(eventIdOfPush), isNot(contains(block.eventId)));
    });

    test(
      'bob can\'t turn alice\'s block off, and the server refuses',
      () async {
        expect(gruppechatScreenshotSwitch(bobChat, l10n).enabled, isFalse);
        // Even though bob is an admin of the direct chat, as alice is
        expect(bobChat.ownPowerLevel, 100);
        for (final content in [
          <String, Object?>{},
          {'blocked': false},
        ]) {
          expect(
            await isForbidden(
              () => bob.setRoomStateWithKey(
                bobChat.id,
                gruppechatScreenshotsType,
                alice.userID!,
                content,
              ),
            ),
            isTrue,
          );
        }
        // His own "off" doesn't touch hers
        await setBlock(bobChat, false);
        await arrives(
          bobTimeline,
          "bob's own off",
          (e) => e.eventId == blockEvents.last,
        );
        expect(gruppechatScreenshotBlockers(bobChat), [alice.userID]);
        expect(gruppechatScreenshotBlockers(aliceChat), [alice.userID]);
      },
    );

    test('with blocks of both, it stays blocked until both are off', () async {
      await setBlock(bobChat, true);
      await eventually(
        'alice sees both blocks',
        () => gruppechatScreenshotBlockers(aliceChat).length == 2,
      );
      // Bob's own block is his to turn off, alice's is still on
      final bobSwitch = gruppechatScreenshotSwitch(bobChat, l10n);
      expect((bobSwitch.on, bobSwitch.enabled), (true, true));
      expect(
        bobSwitch.subtitle,
        contains(
          l10n.gruppechatScreenshotsAlsoBlockedBy(nameOf(bobChat, alice)),
        ),
      );

      await setBlock(aliceChat, false);
      await eventually(
        'bob sees alice has turned hers off',
        () => gruppechatScreenshotBlockers(bobChat).length == 1,
      );
      expect(gruppechatScreenshotBlockers(aliceChat), [bob.userID]);
      expect(gruppechatScreenshotsBlocked(aliceChat), isTrue);
      expect(GruppechatSecureWindow.secure, isTrue);
      final aliceSwitch = gruppechatScreenshotSwitch(aliceChat, l10n);
      expect((aliceSwitch.on, aliceSwitch.enabled), (true, false));
      expect(
        aliceSwitch.subtitle,
        contains(l10n.gruppechatScreenshotsBlockedBy(nameOf(aliceChat, bob))),
      );

      await setBlock(bobChat, false);
      await eventually(
        'alice sees the chat unblocked',
        () => !gruppechatScreenshotsBlocked(aliceChat),
      );
      expect(gruppechatScreenshotsBlocked(bobChat), isFalse);
      expect(GruppechatSecureWindow.secure, isFalse);
      expect(gruppechatCanDownloadTranscript(bobChat), isTrue);
    });

    test('alice turning hers off lifts it', () async {
      await setBlock(aliceChat, true);
      await eventually(
        "bob's window is kept secure",
        () => GruppechatSecureWindow.secure,
      );
      await setBlock(aliceChat, false);
      await eventually(
        "bob's window is no longer kept secure",
        () => !GruppechatSecureWindow.secure,
      );
      expect(gruppechatScreenshotsBlocked(bobChat), isFalse);
      final bobSwitch = gruppechatScreenshotSwitch(bobChat, l10n);
      expect((bobSwitch.on, bobSwitch.enabled), (false, true));
      // Bob closes the chat
      GruppechatSecureWindow.hide(bobsChatPage);
      expect(GruppechatSecureWindow.secure, isFalse);
    });

    test(
      'none of it shows in the chat or the downloaded conversation',
      () async {
        await eventually(
          'bob has all the changes',
          () => blockEvents.every(
            (id) => bobTimeline.events.any((e) => e.eventId == id),
          ),
        );
        final visible = bobTimeline.events.filterByVisibleInGui();
        expect(
          visible.where((e) => e.type == gruppechatScreenshotsType),
          isEmpty,
        );
        expect(visible.map((e) => e.eventId), containsAll(<String>[hello]));
        // The chat list still shows the last message
        expect(bobChat.lastEvent?.type, isNot(gruppechatScreenshotsType));

        final markdown = await buildChatTranscript(bobChat, l10n);
        printOnFailure(markdown);
        expect(markdown, contains('Hei Bob'));
        expect(markdown, contains('Ingen skjermbilder'));
        expect(markdown, isNot(contains(gruppechatScreenshotsType)));

        // No push about any of it
        final pushes = await testServer.recorded('pushes');
        expect(
          pushes.map(eventIdOfPush).toSet().intersection(blockEvents.toSet()),
          isEmpty,
        );
      },
    );

    test('a block of someone who left stops counting', () async {
      final (aliceWithCarol, carolChat) = await directChat(alice, carol);
      await gruppechatSetScreenshotBlock(carolChat, true);
      await eventually(
        'alice sees carol\'s block',
        () => gruppechatScreenshotsBlocked(aliceWithCarol),
      );
      await carolChat.leave();
      await eventually(
        'alice sees carol has left, and the block with her',
        () =>
            aliceWithCarol
                    .getState(EventTypes.RoomMember, carol.userID!)
                    ?.content['membership'] ==
                'leave' &&
            !gruppechatScreenshotsBlocked(aliceWithCarol),
      );
      expect(gruppechatCanDownloadTranscript(aliceWithCarol), isTrue);
      // Her block is still there; invited back, it counts again
      await aliceWithCarol.invite(carol.userID!);
      await eventually(
        'alice sees carol invited, and blocking again',
        () => gruppechatScreenshotsBlocked(aliceWithCarol),
      );
      expect(gruppechatScreenshotBlockers(aliceWithCarol), [carol.userID]);
    });

    test('in a group, only moderators may turn it on', () async {
      final group = await newGroup(alice, [bob, carol], name: 'Skjerm');
      final channel = group.firstChannel;
      final bobsChannel = bob.getRoomById(channel)!;
      final carolsChannel = carol.getRoomById(channel)!;
      final alicesChannel = alice.getRoomById(channel)!;

      expect(gruppechatCanSetScreenshotBlock(bobsChannel), isFalse);
      expect(gruppechatScreenshotSwitch(bobsChannel, l10n).enabled, isFalse);
      expect(
        await isForbidden(
          () => gruppechatSetScreenshotBlock(bobsChannel, true),
        ),
        isTrue,
      );
      expect(gruppechatScreenshotsBlocked(alicesChannel), isFalse);

      // Alice, the group's admin, may
      expect(gruppechatCanSetScreenshotBlock(alicesChannel), isTrue);
      await gruppechatSetScreenshotBlock(alicesChannel, true);
      await eventually(
        'carol sees the group chat blocked',
        () => gruppechatScreenshotsBlocked(carolsChannel),
      );
      expect(gruppechatWindowSecure([carolsChannel]), isTrue);
      expect(gruppechatCanDownloadTranscript(carolsChannel), isFalse);
      // The group's other chats aren't
      final space = carol.getRoomById(group.spaceId)!;
      expect(gruppechatScreenshotsBlocked(space), isFalse);
      // Nothing in carol's chat list either
      expect(carolsChannel.lastEvent?.type, isNot(gruppechatScreenshotsType));
    });
  });
}
