// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Typing a bot's commands: a bot in the chat lists its commands in its
// membership, as the feedback bot does (bot/lib/src/commands.dart), and
// the app suggests them as soon as someone types «!»
// (lib/gruppechat/bot_commands.dart, used by pages/chat/input_bar.dart).
// Commands only the bot's owner may use are suggested only to the owner.

@Timeout(Duration(minutes: 2))
library;

import 'package:fluffychat/gruppechat/bot_commands.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'utils/test_server.dart';

void main() {
  group('Bot commands', skip: skipWithoutTestServer, () {
    late Client alice;
    late Client bob;
    late Client carol;
    late Room aliceRoom;
    late Room bobRoom;

    setUpAll(() async {
      alice = await logIn('alice');
      bob = await logIn('bob');
      carol = await logIn('carol');
      final roomId = await alice.createGroupChat(
        groupName: 'Ønsker og feil',
        enableEncryption: true,
        invite: [bob.userID!, carol.userID!],
      );
      aliceRoom = await joined(alice, roomId);
      bobRoom = await accept(bob, roomId);
      final carolRoom = await accept(carol, roomId);

      // carol plays the bot, whose owner is bob, and lists its commands
      // the way the feedback bot does
      final membership = carolRoom.getState(
        EventTypes.RoomMember,
        carol.userID!,
      )!;
      await carol.setRoomStateWithKey(
        roomId,
        EventTypes.RoomMember,
        carol.userID!,
        {
          ...membership.content,
          'membership': Membership.join.name,
          gruppechatBotCommandsKey: {
            'owner': bob.userID,
            'commands': [
              {
                'command': '!status',
                'description': 'Hva som står på lista',
                'owner_only': false,
              },
              {
                'command': '!sorter',
                'description': 'Sorter lista på nytt',
                'owner_only': true,
              },
            ],
          },
        },
      );
    });
    tearDownAll(logOutEveryone);

    test('typing «!» suggests the bot\'s commands', () async {
      // bob opens the chat, as alice does next
      await gruppechatPrepareBotCommands(bobRoom);
      final suggestions = await valueOf(
        'bob sees the bot\'s commands',
        () => gruppechatBotCommandSuggestions(bobRoom, '!').nullIfEmpty,
      );
      expect(suggestions.map((c) => c.command), ['!status', '!sorter']);
      expect(suggestions.first.description, 'Hva som står på lista');
      expect(
        gruppechatBotCommandSuggestions(bobRoom, '!st').map((c) => c.command),
        ['!status'],
      );
    });

    test('only the owner gets the owner\'s commands', () async {
      await gruppechatPrepareBotCommands(aliceRoom);
      final suggestions = await valueOf(
        'alice sees the bot\'s commands',
        () => gruppechatBotCommandSuggestions(aliceRoom, '!').nullIfEmpty,
      );
      expect(suggestions.map((c) => c.command), ['!status']);
    });

    test('nothing is suggested in the middle of a message', () {
      expect(gruppechatBotCommandSuggestions(bobRoom, 'Hei !st'), isEmpty);
      expect(gruppechatBotCommandSuggestions(bobRoom, '!status '), isEmpty);
    });
  });
}

extension<T> on List<T> {
  List<T>? get nullIfEmpty => this.isEmpty ? null : this;
}
