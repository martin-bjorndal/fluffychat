// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Who blocks screenshots of a chat, whether the app's window has to be kept
// secure, and how the setting shows in the chat's details
// (lib/gruppechat/screenshot_block.dart).

import 'dart:ui' show Locale;

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/gruppechat/chat_transcript.dart';
import 'package:fluffychat/gruppechat/matrix_group.dart';
import 'package:fluffychat/gruppechat/new_chat_power_levels.dart';
import 'package:fluffychat/gruppechat/screenshot_block.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/test_client.dart';

void main() {
  late L10n l10n;
  late Client client;
  late String me;
  const bob = '@bob:example.invalid';
  const carol = '@carol:example.invalid';
  var n = 0;

  setUpAll(() async {
    // Unknown events shown too, so the block would show if it weren't hidden
    SharedPreferences.setMockInitialValues({
      'chat.fluffy.hideUnknownEvents': false,
    });
    await AppSettings.init(loadWebConfigFile: false);
    l10n = await lookupL10n(const Locale('nb'));
    client = await prepareTestClient(loggedIn: true);
    me = client.userID!;
  });

  Event state(
    Room room,
    String type,
    String stateKey,
    Map<String, Object?> content, {
    String? sender,
  }) => Event(
    type: type,
    content: content,
    senderId: sender ?? (stateKey.startsWith('@') ? stateKey : me),
    stateKey: stateKey,
    eventId: '\$state${n++}',
    originServerTs: DateTime(2026, 11, 22, 9, n),
    room: room,
  );

  /// A direct chat of this user with bob and carol, as members with the
  /// given memberships, where everyone may send the block (as in a direct
  /// chat) unless [blockLevel] says otherwise.
  Room chat({
    String bobIs = 'join',
    String? carolIs = 'join',
    int blockLevel = 0,
  }) {
    final room = Room(
      id: '!chat${n++}:example.invalid',
      client: client,
      membership: Membership.join,
    );
    room.setState(
      state(room, EventTypes.RoomPowerLevels, '', {
        'users': {me: 50},
        'users_default': 0,
        'state_default': 50,
        'events': {gruppechatScreenshotsType: blockLevel},
      }),
    );
    for (final (id, membership, name) in [
      (me, 'join', 'Meg'),
      (bob, bobIs, 'Bob'),
      if (carolIs != null) (carol, carolIs, 'Carol'),
    ]) {
      room.setState(
        state(room, EventTypes.RoomMember, id, {
          'membership': membership,
          'displayname': name,
        }),
      );
    }
    return room;
  }

  void block(Room room, String userId, {bool on = true, String? sender}) =>
      room.setState(
        state(
          room,
          gruppechatScreenshotsType,
          userId,
          on ? {'blocked': true} : {},
          sender: sender,
        ),
      );

  group('who blocks', () {
    test('nobody, until someone turns it on', () {
      final room = chat();
      expect(gruppechatScreenshotBlockers(room), isEmpty);
      expect(gruppechatScreenshotsBlocked(room), isFalse);
      block(room, bob);
      expect(gruppechatScreenshotBlockers(room), [bob]);
      expect(gruppechatScreenshotsBlocked(room), isTrue);
      expect(gruppechatHasOwnScreenshotBlock(room), isFalse);
    });

    test('everyone who has their own on, until they turn it off', () {
      final room = chat();
      block(room, carol);
      block(room, me);
      block(room, bob);
      expect(gruppechatScreenshotBlockers(room), [bob, carol, me]..sort());
      expect(gruppechatHasOwnScreenshotBlock(room), isTrue);
      block(room, carol, on: false);
      block(room, me, on: false);
      expect(gruppechatScreenshotBlockers(room), [bob]);
      expect(gruppechatHasOwnScreenshotBlock(room), isFalse);
      block(room, bob, on: false);
      expect(gruppechatScreenshotsBlocked(room), isFalse);
    });

    test('only the person whose key it is counts', () {
      final room = chat();
      // What the server would refuse, should it ever be there
      block(room, bob, sender: carol);
      room.setState(
        state(room, gruppechatScreenshotsType, '', {'blocked': true}),
      );
      room.setState(
        state(room, gruppechatScreenshotsType, bob, {'blocked': 'yes'}),
      );
      expect(gruppechatScreenshotsBlocked(room), isFalse);
    });

    test('invited members count, those who left don\'t', () {
      for (final (membership, counts) in [
        ('join', true),
        ('invite', true),
        ('leave', false),
        ('ban', false),
        ('knock', false),
      ]) {
        final room = chat(bobIs: membership);
        block(room, bob);
        expect(
          gruppechatScreenshotsBlocked(room),
          counts,
          reason: 'bob is $membership',
        );
      }
    });

    test('someone the app knows nothing about yet counts, to be safe', () {
      final room = chat(carolIs: null);
      block(room, carol);
      expect(gruppechatScreenshotBlockers(room), [carol]);
    });
  });

  test('the window is secure while any chat on screen blocks', () {
    final open = chat();
    final blocked = chat();
    block(blocked, bob);
    expect(gruppechatWindowSecure([]), isFalse);
    expect(gruppechatWindowSecure([open]), isFalse);
    expect(gruppechatWindowSecure([open, blocked]), isTrue);
  });

  test('a browser hides a chat that blocks, the Android app shows it', () {
    final open = chat();
    final blocked = chat();
    block(blocked, bob);
    expect(gruppechatHiddenHere(open, canSecureWindow: false), isFalse);
    expect(gruppechatHiddenHere(blocked, canSecureWindow: false), isTrue);
    expect(gruppechatHiddenHere(blocked, canSecureWindow: true), isFalse);
    // The tests run outside Android, where the window can't be secured
    expect(gruppechatCanSecureWindow, isFalse);
    expect(gruppechatHiddenHere(blocked), isTrue);
  });

  test('open chat pages keep the window secure as their chats change', () {
    final first = chat();
    final second = chat();
    final page1 = Object();
    final page2 = Object();
    GruppechatSecureWindow.show(page1, first);
    expect(GruppechatSecureWindow.secure, isFalse);
    block(second, bob);
    GruppechatSecureWindow.show(page2, second);
    expect(GruppechatSecureWindow.secure, isTrue);
    GruppechatSecureWindow.hide(page2);
    expect(GruppechatSecureWindow.secure, isFalse);
    // A block that comes in while the chat is open, as the sync delivers it
    block(first, bob);
    GruppechatSecureWindow.update();
    expect(GruppechatSecureWindow.secure, isTrue);
    GruppechatSecureWindow.hide(page1);
    expect(GruppechatSecureWindow.secure, isFalse);
  });

  group('the setting', () {
    test('off: whoever may, can turn it on', () {
      final s = gruppechatScreenshotSwitch(chat(), l10n);
      expect((s.on, s.enabled), (false, true));
      expect(s.subtitle, l10n.gruppechatBlockScreenshotsDescription);
      expect(s.subtitle, contains('skjermopptak'));
      final notAllowed = gruppechatScreenshotSwitch(
        chat(blockLevel: 100),
        l10n,
      );
      expect((notAllowed.on, notAllowed.enabled), (false, false));
    });

    test('on by me: I can turn it off', () {
      final room = chat();
      block(room, me);
      final s = gruppechatScreenshotSwitch(room, l10n);
      expect((s.on, s.enabled), (true, true));
      expect(s.subtitle, l10n.gruppechatBlockScreenshotsDescription);
    });

    test('on by others: shown on, theirs to turn off, and who it is', () {
      final room = chat();
      block(room, bob);
      block(room, carol);
      final s = gruppechatScreenshotSwitch(room, l10n);
      expect((s.on, s.enabled), (true, false));
      expect(s.subtitle, endsWith('Slått på av Bob, Carol'));
    });

    test('on by me and others: mine to turn off, and theirs stay', () {
      final room = chat();
      block(room, me);
      block(room, bob);
      final s = gruppechatScreenshotSwitch(room, l10n);
      expect((s.on, s.enabled), (true, true));
      expect(s.subtitle, endsWith('Også slått på av Bob'));
    });
  });

  test('a blocked chat can\'t be downloaded', () {
    final room = chat();
    expect(gruppechatCanDownloadTranscript(room), isTrue);
    block(room, bob);
    expect(gruppechatCanDownloadTranscript(room), isFalse);
  });

  test('turning it on or off leaves no line in the chat', () {
    final room = chat();
    final event = state(room, gruppechatScreenshotsType, bob, {
      'blocked': true,
    });
    expect(AppSettings.hideUnknownEvents.value, isFalse);
    expect(event.isVisibleInGui, isFalse);
    expect([event].filterByVisibleInGui(), isEmpty);
  });

  test('the block is kept in memory for the chat list, and new group chats '
      'leave it to moderators', () {
    expect(gruppechatImportantStateEvents, contains(gruppechatScreenshotsType));
    final events = newChatPowerLevels()['events'] as Map<String, Object?>;
    expect(events[gruppechatScreenshotsType], 50);
  });
}
