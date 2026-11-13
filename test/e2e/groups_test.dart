// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Group chats with channels: setting up group features, permissions,
// nicknames, roles and @role mentions, and backgrounds, with alice (who
// makes the group), bob and carol.

@Timeout(Duration(minutes: 4))
library;

import 'dart:typed_data';
import 'dart:ui' show Locale;

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/gruppechat/avatar_letters.dart';
import 'package:fluffychat/gruppechat/change_notices.dart';
import 'package:fluffychat/gruppechat/delete_room.dart';
import 'package:fluffychat/gruppechat/group_state.dart';
import 'package:fluffychat/gruppechat/matrix_group.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/test_server.dart';

void main() {
  group('Setting up a group', skip: skipWithoutTestServer, () {
    late Client alice;
    late Client bob;
    late TestGroup group;
    GruppechatGroup aliceGroup() =>
        GruppechatGroup(alice.getRoomById(group.spaceId)!);
    GruppechatGroup bobGroup() =>
        GruppechatGroup.of(bob.getRoomById(group.firstChannel)!)!;

    setUpAll(() async {
      alice = await logIn('alice');
      bob = await logIn('bob');
      group = await newGroup(alice, [bob], setUp: false);
    });
    tearDownAll(logOutEveryone);

    test('a channel belongs to its group', () {
      expect(bobGroup().space.id, group.spaceId);
    });

    test('a new group needs setup, which only its owner can do', () {
      expect(aliceGroup().needsSetup, isTrue);
      expect(aliceGroup().canSetUp, isTrue);
      expect(bobGroup().canSetUp, isFalse);
    });

    test('before setup, members cannot set nicknames', () async {
      expect(bobGroup().canSetNicknames, isFalse);
      expect(
        await isForbidden(
          () => bobGroup().setNickname(alice.userID!, 'For tidlig'),
        ),
        isTrue,
      );
    });

    test('opening a group chat sets it up for an admin only', () async {
      // What the chat page does when it opens (lib/pages/chat/chat.dart)
      await bobGroup().setUpIfNeeded();
      expect(bobGroup().needsSetup, isTrue);
      await aliceGroup().setUpIfNeeded();
      await eventually('bob sees the setup', () => !bobGroup().needsSetup);
    });

    test('then members may set nicknames and backgrounds, not roles', () {
      expect(bobGroup().canSetNicknames, isTrue);
      expect(bobGroup().canSetBackground, isTrue);
      expect(bobGroup().canSetChatColor, isTrue);
      expect(bobGroup().canManageRoles, isFalse);
      expect(aliceGroup().canManageRoles, isTrue);
    });
  });

  group('Nicknames', skip: skipWithoutTestServer, () {
    late Client alice;
    late Client bob;
    late Client carol;
    late TestGroup group;
    GruppechatGroup groupOf(Client client) =>
        GruppechatGroup(client.getRoomById(group.spaceId)!);
    String nameIn(Client viewer, String channel, String userId) => viewer
        .getRoomById(group.channels[channel]!)!
        .unsafeGetUserFromMemoryOrFallback(userId)
        .groupDisplayname();

    setUpAll(() async {
      alice = await logIn('alice');
      bob = await logIn('bob');
      carol = await logIn('carol');
      group = await newGroup(
        alice,
        [bob, carol],
        channels: ['general', 'spill'],
      );
    });
    tearDownAll(logOutEveryone);

    test('anyone can name anyone, in every channel', () async {
      await groupOf(bob).setNickname(carol.userID!, 'Kaptein');
      for (final channel in ['general', 'spill']) {
        await eventually(
          'alice sees the nickname in $channel',
          () => nameIn(alice, channel, carol.userID!) == 'Kaptein',
        );
      }
      await eventually(
        'carol sees her own nickname',
        () => nameIn(carol, 'general', carol.userID!) == 'Kaptein',
      );
      expect(groupOf(alice).state.nicknameOf(carol.userID!)?.setBy, bob.userID);
    });

    test('an empty nickname removes it', () async {
      await groupOf(alice).setNickname(carol.userID!, '');
      await eventually(
        'the nickname is gone',
        () => groupOf(bob).state.nicknameOf(carol.userID!) == null,
      );
      expect(nameIn(bob, 'general', carol.userID!), isNot('Kaptein'));
    });

    test('a lock keeps others from renaming you', () async {
      await groupOf(bob).setNickname(carol.userID!, 'Før låsen');
      await eventually(
        'carol sees it',
        () => groupOf(carol).state.nicknameOf(carol.userID!) != null,
      );
      expect(
        await isForbidden(
          () => bob.setRoomStateWithKey(
            group.spaceId,
            GruppechatEventTypes.nicknameLock,
            carol.userID!,
            {'locked': false},
          ),
        ),
        isTrue,
        reason: 'only carol may lock or unlock her own nickname',
      );
      await groupOf(carol).setOwnNicknameLocked(true);
      await eventually(
        'bob sees the lock',
        () => groupOf(bob).state.isNicknameLocked(carol.userID!),
      );
      expect(
        groupOf(bob).state.nicknameOf(carol.userID!),
        isNull,
        reason: 'the lock hides the nickname bob gave her',
      );
      await groupOf(carol).setNickname(carol.userID!, 'Carol selv');
      await eventually(
        'bob sees the name she chose',
        () => nameIn(bob, 'general', carol.userID!) == 'Carol selv',
      );
      await groupOf(carol).setOwnNicknameLocked(false);
    });

    test('admins can make nicknames moderator-only', () async {
      // As the group permissions in the chat's permission settings
      // (lib/gruppechat/group_permission_tiles.dart)
      Future<void> nicknameLevel(int level) async {
        final powerLevels = alice
            .getRoomById(group.spaceId)!
            .getState(EventTypes.RoomPowerLevels)!
            .content;
        await alice.setRoomStateWithKey(
          group.spaceId,
          EventTypes.RoomPowerLevels,
          '',
          {
            ...powerLevels,
            'events': {
              ...?powerLevels.tryGetMap<String, Object?>('events'),
              GruppechatEventTypes.nickname: level,
            },
          },
        );
        await eventually(
          'bob sees nicknames at level $level',
          () => groupOf(bob).canSetNicknames == (level == 0),
        );
      }

      expect(
        groupEventPowerLevels[GruppechatEventTypes.nickname],
        0,
        reason: 'everyone may set nicknames by default',
      );
      await nicknameLevel(50);
      expect(
        await isForbidden(
          () => groupOf(bob).setNickname(alice.userID!, 'Sjefen'),
        ),
        isTrue,
      );
      await groupOf(alice).setNickname(bob.userID!, 'Moderert');
      await nicknameLevel(0);
      await groupOf(bob).setNickname(alice.userID!, 'Sjefen');
      await eventually(
        'carol sees it',
        () => nameIn(carol, 'spill', alice.userID!) == 'Sjefen',
      );
    });
  });

  group('Roles', skip: skipWithoutTestServer, () {
    late Client alice;
    late Client bob;
    late Client carol;
    late TestGroup group;
    late String roleId;
    GruppechatGroup groupOf(Client client) =>
        GruppechatGroup(client.getRoomById(group.spaceId)!);
    Room channel(Client client) => client.getRoomById(group.firstChannel)!;

    setUpAll(() async {
      alice = await logIn('alice');
      bob = await logIn('bob');
      carol = await logIn('carol');
      group = await newGroup(alice, [bob, carol]);
    });
    tearDownAll(logOutEveryone);

    test('only moderators create roles', () async {
      expect(
        await isForbidden(() => groupOf(bob).createRole('Hackere')),
        isTrue,
      );
      roleId = await groupOf(alice).createRole('Spillkveld');
      expect(roleId, 'spillkveld');
      await groupOf(alice).setMemberRoles(bob.userID!, {roleId});
      await eventually(
        'bob sees his role',
        () => groupOf(bob).state.roleIdsOf(bob.userID!).contains(roleId),
      );
    });

    test('the input bar suggests the role', () {
      expect(
        gruppechatRoleSuggestions(
          channel(carol),
          'spill',
        ).map((s) => s['mention']),
        ['@spillkveld'],
      );
    });

    test('an @role mention notifies the people who have it', () async {
      final bobTimeline = await channel(bob).getTimeline();
      final carolTimeline = await channel(carol).getTimeline();
      await channel(alice).sendTextEvent('@spillkveld pizza kl 8?');
      final forBob = await arrives(
        bobTimeline,
        'the mention',
        (e) => e.body == '@spillkveld pizza kl 8?',
      );
      final forCarol = await arrives(
        carolTimeline,
        'the mention',
        (e) => e.body == '@spillkveld pizza kl 8?',
      );
      expect(forBob.mentionsOwnGroupRole, isTrue);
      expect(forCarol.mentionsOwnGroupRole, isFalse);

      await channel(bob).sendTextEvent('@spillkveld jeg også');
      final own = await arrives(
        bobTimeline,
        'his own mention',
        (e) => e.body == '@spillkveld jeg også',
      );
      expect(own.mentionsOwnGroupRole, isFalse);
    });

    test('a role can be invited to a channel', () async {
      final roomId = await alice.createGroupChat(
        groupName: 'kun-spillkveld',
        preset: CreateRoomPreset.privateChat,
      );
      await alice.getRoomById(group.spaceId)!.setSpaceChild(roomId);
      final invited = await groupOf(
        alice,
      ).inviteRole(alice.getRoomById(roomId)!, roleId);
      expect(invited, [bob.userID]);
      await accept(bob, roomId);
      expect(carol.getRoomById(roomId)?.membership, isNot(Membership.invite));
    });

    test('renaming keeps the members, deleting removes it', () async {
      await groupOf(
        alice,
      ).renameRole(groupOf(alice).state.roleById(roleId)!, 'Spill');
      await eventually(
        'bob sees the new name',
        () => groupOf(bob).state.roleById(roleId)?.name == 'Spill',
      );
      expect(groupOf(bob).state.roleIdsOf(bob.userID!), contains(roleId));
      await groupOf(alice).deleteRole(roleId);
      await eventually(
        'bob sees it gone',
        () => groupOf(bob).state.roles.isEmpty,
      );
      expect(groupOf(bob).state.roleIdsOf(bob.userID!), isEmpty);
    });
  });

  group('Backgrounds', skip: skipWithoutTestServer, () {
    late Client alice;
    late Client bob;
    late Client carol;
    late TestGroup group;
    final midnight = groupBackgroundPresets[0].$2;
    final forest = groupBackgroundPresets[1].$2;
    final sunset = groupBackgroundPresets[3].$2;
    GruppechatGroup groupOf(Client client) =>
        GruppechatGroup(client.getRoomById(group.spaceId)!);
    Room channel(Client client, String name) =>
        client.getRoomById(group.channels[name]!)!;
    GroupBackground? shownIn(Client client, String name) =>
        channel(client, name).gruppechatBackground(enabled: true);
    Future<void> shows(Client client, String name, GroupBackground? expected) =>
        eventually(
          '${client.userID} sees the right background in $name',
          () =>
              shownIn(client, name)?.toContent().toString() ==
              expected?.toContent().toString(),
        );

    setUpAll(() async {
      alice = await logIn('alice');
      bob = await logIn('bob');
      carol = await logIn('carol');
      group = await newGroup(
        alice,
        [bob, carol],
        channels: ['general', 'spill', 'musikk'],
      );
    });
    tearDownAll(logOutEveryone);

    test('a member sets the group background for every channel', () async {
      await groupOf(bob).setBackground(sunset);
      for (final name in ['general', 'spill', 'musikk']) {
        await shows(alice, name, sunset);
      }
      final shown = shownIn(alice, 'general')!;
      expect(shown.kind, GroupBackgroundKind.gradient);
      expect(shown.opacity, 0.6);
    });

    test('each channel can have its own, independent of the others', () async {
      await groupOf(bob).setChannelBackground(channel(bob, 'spill'), midnight);
      await groupOf(
        carol,
      ).setChannelBackground(channel(carol, 'musikk'), forest);
      await shows(alice, 'spill', midnight);
      await shows(alice, 'musikk', forest);
      await shows(alice, 'general', sunset);
      await shows(bob, 'musikk', forest);
      await shows(carol, 'spill', midnight);
    });

    test('a channel can turn the background off', () async {
      await groupOf(alice).setChannelBackground(
        channel(alice, 'musikk'),
        const GroupBackground(kind: GroupBackgroundKind.none),
      );
      await shows(bob, 'musikk', null);
      await shows(bob, 'general', sunset);
    });

    test('clearing a channel brings back the group background', () async {
      await groupOf(carol).setChannelBackground(channel(carol, 'spill'), null);
      await groupOf(carol).setChannelBackground(channel(carol, 'musikk'), null);
      await shows(alice, 'spill', sunset);
      await shows(alice, 'musikk', sunset);
    });

    // Wish from 1.1.23: chats in pink, with flowers, or in people's own
    // colours, as a pattern, a gradient or one colour
    test('someone makes a channel their own pattern', () async {
      final own = groupBackgroundPresets[0].$2
          .withKind(GroupBackgroundKind.pattern)
          .copyWith(pattern: GroupBackgroundPattern.hearts)
          .withColor(0, groupBackgroundPalette[1])
          .withColor(1, groupBackgroundPalette[4]);
      await groupOf(bob).setChannelBackground(channel(bob, 'spill'), own);
      await shows(alice, 'spill', own);
      await shows(carol, 'spill', own);
      final shown = shownIn(carol, 'spill')!;
      expect(shown.pattern, GroupBackgroundPattern.hearts);
      expect(shown.colors, [
        groupBackgroundPalette[1],
        groupBackgroundPalette[4],
      ]);
      // The others keep the group's
      await shows(carol, 'general', sunset);
      await groupOf(bob).setChannelBackground(channel(bob, 'spill'), null);
      await shows(alice, 'spill', sunset);
    });

    test('a picture works as background', () async {
      final mxc = await bob.uploadContent(
        Uint8List.fromList(List.filled(64, 200)),
        filename: 'bakgrunn.jpg',
        contentType: 'image/jpeg',
      );
      final picture = GroupBackground(
        kind: GroupBackgroundKind.image,
        url: mxc,
        opacity: 0.8,
        blur: 4,
      );
      await groupOf(bob).setBackground(picture);
      await shows(carol, 'general', picture);
      expect(shownIn(carol, 'general')!.url, mxc);
    });

    test('hiding backgrounds is up to each account', () async {
      await bob.setShowGroupBackgrounds(false);
      await eventually('bob\'s choice syncs', () => !bob.showGroupBackgrounds);
      expect(alice.showGroupBackgrounds, isTrue);
      expect(
        channel(
          bob,
          'general',
        ).gruppechatBackground(enabled: bob.showGroupBackgrounds),
        isNull,
      );
      await bob.setShowGroupBackgrounds(true);
      await groupOf(alice).setBackground(null);
      await shows(carol, 'general', null);
    });

    test('a direct chat has a background both people can set', () async {
      final (aliceChat, bobChat) = await directChat(alice, bob);
      final chatGroup = bobChat.gruppechatBackgroundGroup!;
      expect(chatGroup.canSetBackground, isTrue);
      await chatGroup.setBackground(forest);
      await eventually(
        'alice sees it',
        () =>
            aliceChat
                .gruppechatBackground(enabled: true)
                ?.toContent()
                .toString() ==
            forest.toContent().toString(),
      );
      await aliceChat.gruppechatBackgroundGroup!.setBackground(null);
      await eventually(
        'bob sees it removed',
        () => bobChat.gruppechatBackground(enabled: true) == null,
      );
    });
  });

  // Wish from 1.1.26: a chat's own colours for its top and bottom bars and
  // its bubbles, leaving the background alone. How the colours look can only
  // be judged on a phone.
  group('Chat colours', skip: skipWithoutTestServer, () {
    late Client alice;
    late Client bob;
    late Client carol;
    late TestGroup group;
    const pink = 0xFFE91E63;
    const teal = 0xFF00897B;
    GruppechatGroup groupOf(Client client) =>
        GruppechatGroup(client.getRoomById(group.spaceId)!);
    Room channel(Client client, String name) =>
        client.getRoomById(group.channels[name]!)!;
    Future<void> shows(Client client, String name, int? color) => eventually(
      '${client.userID} sees the right colour in $name',
      () => channel(client, name).gruppechatChatColor == color,
    );

    setUpAll(() async {
      alice = await logIn('alice');
      bob = await logIn('bob');
      carol = await logIn('carol');
      group = await newGroup(
        alice,
        [bob, carol],
        channels: ['general', 'spill'],
      );
    });
    tearDownAll(logOutEveryone);

    test('a member colours one channel for everyone', () async {
      expect(channel(bob, 'spill').gruppechatChatColor, isNull);
      expect(groupOf(bob).canSetChatColor, isTrue);
      await groupOf(bob).setChatColor(channel(bob, 'spill'), pink);
      await shows(alice, 'spill', pink);
      await shows(carol, 'spill', pink);
      // The other channel, and the background, stay as they were
      expect(channel(carol, 'general').gruppechatChatColor, isNull);
      expect(
        channel(carol, 'spill').gruppechatBackground(enabled: true),
        isNull,
      );
    });

    test('someone else changes it, and anyone can remove it', () async {
      await groupOf(carol).setChatColor(channel(carol, 'spill'), teal);
      await shows(bob, 'spill', teal);
      await groupOf(alice).setChatColor(channel(alice, 'spill'), null);
      await shows(bob, 'spill', null);
      await shows(carol, 'spill', null);
    });

    test('a colour sent see-through is shown solid', () async {
      await bob.setRoomStateWithKey(
        group.spaceId,
        GruppechatEventTypes.chatColor,
        group.channels['general']!,
        {'color': '#80E91E63'},
      );
      await shows(alice, 'general', pink);
      await groupOf(bob).setChatColor(channel(bob, 'general'), null);
    });

    test('a group set up before chat colours gets them when opened', () async {
      // What older versions of the app set up: everything but chat colours
      final space = alice.getRoomById(group.spaceId)!;
      final powerLevels = Map<String, Object?>.from(
        space.getState(EventTypes.RoomPowerLevels)!.content,
      );
      powerLevels['events'] = Map<String, Object?>.from(
        powerLevels['events'] as Map,
      )..remove(GruppechatEventTypes.chatColor);
      await alice.setRoomStateWithKey(
        group.spaceId,
        EventTypes.RoomPowerLevels,
        '',
        powerLevels,
      );
      await eventually(
        'bob may no longer set it',
        () => !groupOf(bob).canSetChatColor,
      );
      expect(groupOf(bob).needsSetup, isTrue);
      // What the chat page does when alice, an admin, opens a chat
      await GruppechatGroup.of(channel(alice, 'general'))!.setUpIfNeeded();
      await eventually('bob may set it', () => groupOf(bob).canSetChatColor);
      await groupOf(bob).setChatColor(channel(bob, 'general'), teal);
      await shows(carol, 'general', teal);
    });

    test('in a direct chat both people can set it', () async {
      final (aliceChat, bobChat) = await directChat(alice, bob);
      final aliceSide = aliceChat.gruppechatBackgroundGroup!;
      final bobSide = bobChat.gruppechatBackgroundGroup!;
      expect(aliceSide.canSetChatColor, isTrue);
      expect(bobSide.canSetChatColor, isTrue);
      await bobSide.setChatColor(bobChat, pink);
      await eventually(
        'alice sees it',
        () => aliceChat.gruppechatChatColor == pink,
      );
      await aliceSide.setChatColor(aliceChat, null);
      await eventually(
        'bob sees it removed',
        () => bobChat.gruppechatChatColor == null,
      );
    });
  });

  // Reported in 1.1.17: a chat named "💔" crashed the screen with "string is
  // not well-formed UTF-16", since its avatar took half of the emoji
  group('A chat named with emojis', skip: skipWithoutTestServer, () {
    late Client alice;
    late Client bob;
    late TestGroup group;

    setUpAll(() async {
      alice = await logIn('alice');
      bob = await logIn('bob');
      group = await newGroup(alice, [bob], channels: ['general', 'spill']);
    });
    tearDownAll(logOutEveryone);

    for (final (channel, name, letters) in [
      ('general', '💔', '💔'),
      ('spill', '💔 Hjertesorg', '💔H'),
    ]) {
      test('"$name" gets an avatar of whole characters', () async {
        // Renamed as the chat details page does
        await alice.getRoomById(group.channels[channel]!)!.setName(name);
        final room = bob.getRoomById(group.channels[channel]!)!;
        await eventually('bob sees the new name', () => room.name == name);
        final shown = room.getLocalizedDisplayname();
        expect(shown, name);
        // What bob's chat list shows (lib/widgets/avatar.dart)
        final avatar = avatarFallbackLetters(shown);
        expect(avatar, letters);
        expect(_wellFormedUtf16(avatar), isTrue);
      });
    }
  });

  group('Deleting a chat', skip: skipWithoutTestServer, () {
    late Client alice;
    late Client bob;
    late Client carol;
    late TestGroup group;

    setUpAll(() async {
      alice = await logIn('alice');
      bob = await logIn('bob');
      carol = await logIn('carol');
      group = await newGroup(
        alice,
        [bob, carol],
        name: 'Slettegruppe',
        channels: ['general', 'old', 'mods', 'more'],
      );
    });
    tearDownAll(logOutEveryone);

    Room aliceRoom(String id) => alice.getRoomById(id)!;

    test('only someone who outranks everyone in it may delete it', () async {
      final channel = group.channels['general']!;
      expect(gruppechatCanDeleteRoom(aliceRoom(channel)), isTrue);
      expect(gruppechatCanDeleteRoom(bob.getRoomById(channel)!), isFalse);
      final (aliceDirect, _) = await directChat(alice, bob);
      expect(gruppechatCanDeleteRoom(aliceDirect), isFalse);
    });

    test('a deleted channel is gone for everyone, and stays shut', () async {
      final channel = group.channels['old']!;
      // Open to anyone in the group, so being put out isn't enough
      await aliceRoom(channel).setJoinRules(JoinRules.public);
      await gruppechatDeleteRoom(aliceRoom(channel), reason: 'Sletta');
      for (final client in [bob, carol]) {
        await eventually(
          '${client.userID} is out of the deleted channel',
          () => client.getRoomById(channel) == null,
        );
      }
      expect(alice.getRoomById(channel), isNull);
      await eventually(
        'bob no longer sees it in the group',
        () => bob
            .getRoomById(group.spaceId)!
            .spaceChildren
            .every((child) => child.roomId != channel),
      );
      // Nobody is left in it to let him back in
      await expectLater(bob.joinRoom(channel), throwsA(isA<MatrixException>()));
    });

    test('another admin in it keeps it from being deleted', () async {
      final channel = group.channels['mods']!;
      await aliceRoom(channel).setPower(bob.userID!, 100);
      // bob steps down again afterwards, as only he can
      addTearDown(() async {
        await bob.getRoomById(channel)!.setPower(bob.userID!, 0);
        await eventually(
          'alice sees bob step down',
          () =>
              aliceRoom(channel).getPowerLevelByUserId(bob.userID!).level == 0,
        );
      });
      await eventually(
        'alice sees bob as admin',
        () =>
            aliceRoom(channel).getPowerLevelByUserId(bob.userID!).level == 100,
      );
      expect(gruppechatCanDeleteRoom(aliceRoom(channel)), isFalse);
      // Nor the group it is in
      expect(gruppechatCanDeleteRoom(aliceRoom(group.spaceId)), isFalse);
    });

    test('a deleted group takes all its channels with it', () async {
      final space = aliceRoom(group.spaceId);
      expect(gruppechatCanDeleteRoom(space), isTrue);
      await gruppechatDeleteRoom(space, reason: 'Sletta');
      final rooms = [group.spaceId, ...group.channels.values];
      for (final client in [alice, bob, carol]) {
        await eventually(
          '${client.userID} is out of the group and every channel',
          () => rooms.every((id) => client.getRoomById(id) == null),
        );
      }
    });
  });

  group('Lines saying who changed what', skip: skipWithoutTestServer, () {
    late Client alice;
    late Client bob;
    late Client carol;
    late TestGroup group;
    late L10n l10n;
    late String pushkey;
    late Timeline aliceTimeline;
    GruppechatGroup groupOf(Client client) =>
        GruppechatGroup(client.getRoomById(group.spaceId)!);
    Room channel(Client client, String name) =>
        client.getRoomById(group.channels[name]!)!;
    String nameOf(Client client) => channel(
      alice,
      'spill',
    ).unsafeGetUserFromMemoryOrFallback(client.userID!).calcDisplayname();
    Future<Event> lineFrom(Client sender, String kind) => arrives(
      aliceTimeline,
      'a $kind line from ${sender.userID}',
      (event) =>
          event.type == gruppechatChangeType &&
          event.senderId == sender.userID &&
          event.content['kind'] == kind,
    );

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      await AppSettings.init(loadWebConfigFile: false);
      l10n = await lookupL10n(const Locale('nb'));
      alice = await logIn('alice');
      bob = await logIn('bob');
      carol = await logIn('carol');
      group = await newGroup(
        alice,
        [bob, carol],
        channels: ['general', 'spill'],
      );
      pushkey = await addPusher(carol);
      aliceTimeline = await channel(alice, 'spill').getTimeline();
    });
    tearDownAll(logOutEveryone);

    test(
      'a nickname set from a channel shows there, with who set it',
      () async {
        // The nickname dialog, opened from the member list of spill
        await changeGroupNickname(
          groupOf(bob),
          carol.userID!,
          'Kaptein',
          from: channel(bob, 'spill'),
        );
        final line = await lineFrom(bob, 'nickname');
        expect(channel(alice, 'spill').encrypted, isTrue);
        expect(line.type, gruppechatChangeType, reason: 'sent unencrypted');
        expect(line.isVisibleInGui, isTrue);
        expect(line.isCollapsedState, isFalse);
        expect(
          groupChangeText(line, l10n),
          l10n.gruppechatGaveNickname(nameOf(bob), nameOf(carol), 'Kaptein'),
          reason: 'their own names, not the nickname just given',
        );
      },
    );

    test('the line wakes nobody, though it is about carol', () async {
      final line = await lineFrom(bob, 'nickname');
      // A message after it shows that pushes still flow
      final loudId = await channel(alice, 'spill').sendTextEvent('Hallo');
      await waitForPush(pushkey, loudId!);
      final pushes = await testServer.recorded('pushes');
      expect(
        pushes.where((push) => eventIdOfPush(push) == line.eventId),
        isEmpty,
      );
    });

    test('saving the same nickname again says nothing', () async {
      await eventually(
        'bob sees the nickname',
        () => groupOf(bob).state.nicknameOf(carol.userID!)?.name == 'Kaptein',
      );
      await changeGroupNickname(
        groupOf(bob),
        carol.userID!,
        'Kaptein',
        from: channel(bob, 'spill'),
      );
      final afterId = await channel(bob, 'spill').sendTextEvent('Etter');
      await arrives(
        aliceTimeline,
        'the message after',
        (e) => e.eventId == afterId,
      );
      expect(
        aliceTimeline.events.where(
          (e) => e.type == gruppechatChangeType && e.senderId == bob.userID,
        ),
        hasLength(1),
      );
    });

    test('someone removing their own nickname', () async {
      await eventually(
        'carol sees the nickname bob gave her',
        () => groupOf(carol).state.nicknameOf(carol.userID!) != null,
      );
      await changeGroupNickname(
        groupOf(carol),
        carol.userID!,
        '',
        from: channel(carol, 'spill'),
      );
      final line = await lineFrom(carol, 'nickname');
      expect(line.content.containsKey('nickname'), isFalse);
      expect(
        groupChangeText(line, l10n),
        l10n.gruppechatDroppedNickname(nameOf(carol)),
      );
    });

    test('the group background, set from a channel', () async {
      final sunset = groupBackgroundPresets[3].$2;
      // The background menu, opened from spill
      await changeGroupBackground(
        groupOf(bob),
        sunset,
        from: channel(bob, 'spill'),
      );
      final line = await lineFrom(bob, 'group_background');
      expect(
        groupChangeText(line, l10n),
        l10n.gruppechatChangedGroupBackground(nameOf(bob)),
      );
      await groupOf(bob).setBackground(null);
    });

    test('a chat colour', () async {
      final spill = channel(carol, 'spill');
      await changeChatColor(groupOf(carol), spill, 0xFFE91E63);
      final line = await lineFrom(carol, 'chat_color');
      expect(
        groupChangeText(line, l10n),
        l10n.gruppechatChangedChatColor(nameOf(carol)),
      );
      await groupOf(carol).setChatColor(spill, null);
    });

    test("a direct chat's background is the chat's own", () async {
      final (aliceChat, bobChat) = await directChat(alice, bob);
      final forest = groupBackgroundPresets[1].$2;
      await changeGroupBackground(
        bobChat.gruppechatBackgroundGroup!,
        forest,
        from: bobChat,
      );
      final timeline = await aliceChat.getTimeline();
      final line = await arrives(
        timeline,
        'the background line',
        (e) => e.type == gruppechatChangeType,
      );
      expect(line.content['kind'], 'chat_background');
      await bobChat.gruppechatBackgroundGroup!.setBackground(null);
    });

    test('nothing is posted in the space itself', () async {
      final space = groupOf(alice).space;
      final timeline = await space.getTimeline();
      await changeGroupBackground(
        groupOf(alice),
        groupBackgroundPresets[0].$2,
        from: space,
      );
      // alice may write in the space; her message comes after any line
      final afterId = await space.sendTextEvent('Etter');
      await arrives(timeline, 'the message after', (e) => e.eventId == afterId);
      expect(
        timeline.events.where((e) => e.type == gruppechatChangeType),
        isEmpty,
      );
      await groupOf(alice).setBackground(null);
    });
  });
}

/// Whether [text] has no lone halves of surrogate pairs, which Flutter
/// refuses to lay out.
bool _wellFormedUtf16(String text) {
  final units = text.codeUnits;
  for (var i = 0; i < units.length; i++) {
    final unit = units[i];
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      if (i + 1 >= units.length) return false;
      final next = units[++i];
      if (next < 0xDC00 || next > 0xDFFF) return false;
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      return false;
    }
  }
  return true;
}
