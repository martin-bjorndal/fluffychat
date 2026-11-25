// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Typing a bot's commands: a bot in the chat lists its commands in its
// membership, as the feedback bot does (bot/lib/src/commands.dart), and
// the app suggests them as soon as someone types «!»
// (lib/gruppechat/bot_commands.dart, used by pages/chat/input_bar.dart).
// Commands only the bot's owner may use are suggested only to the owner.
// After a command, the app suggests what may follow it (the chat bot's
// models and their prices), and then which bot it is for.

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
              {
                'command': '!modell',
                'description': 'Byt modell',
                'owner_only': false,
                'bot_argument': true,
                'arguments': [
                  {'value': 'opus-5-5', 'description': '\$4 inn / \$20 ut'},
                  {'value': 'haiku-5-5', 'description': '\$0.10 inn'},
                  {'value': 'grok', 'description': 'Nyaste Grok'},
                ],
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
      expect(suggestions.map((c) => c.command), [
        '!status',
        '!sorter',
        '!modell',
      ]);
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
      expect(suggestions.map((c) => c.command), ['!status', '!modell']);
    });

    test(
      'after a command, its models with their prices, then which bot',
      () async {
        await gruppechatPrepareBotCommands(bobRoom);
        final models = await valueOf(
          'bob sees the models',
          () =>
              gruppechatBotCommandSuggestions(bobRoom, '!modell ').nullIfEmpty,
        );
        expect(models.map((c) => c.command), [
          '!modell opus-5-5',
          '!modell haiku-5-5',
          '!modell grok',
        ]);
        expect(models.first.description, '\$4 inn / \$20 ut');
        expect(
          gruppechatBotCommandSuggestions(
            bobRoom,
            '!modell h',
          ).map((c) => c.command),
          ['!modell haiku-5-5'],
        );
        // One bot: no bot to pick
        expect(
          gruppechatBotCommandSuggestions(bobRoom, '!modell grok '),
          isEmpty,
        );

        // alice plays a second bot with the same command
        final membership = aliceRoom.getState(
          EventTypes.RoomMember,
          alice.userID!,
        )!;
        await alice.setRoomStateWithKey(
          aliceRoom.id,
          EventTypes.RoomMember,
          alice.userID!,
          {
            ...membership.content,
            'membership': Membership.join.name,
            'displayname': 'Grokky',
            gruppechatBotCommandsKey: {
              'owner': bob.userID,
              'commands': [
                {
                  'command': '!modell',
                  'description': 'Byt modell',
                  'bot_argument': true,
                },
              ],
            },
          },
        );
        final bots = await valueOf(
          'bob can pick the bot',
          () => gruppechatBotCommandSuggestions(
            bobRoom,
            '!modell grok ',
          ).nullIfEmpty,
        );
        expect(bots.map((c) => c.command).toSet(), {
          '!modell grok carol',
          '!modell grok Grokky',
        });
        expect(
          gruppechatBotCommandSuggestions(
            bobRoom,
            '!modell grok gr',
          ).map((c) => c.command),
          ['!modell grok Grokky'],
        );
        // The same command from two bots is suggested once
        expect(
          gruppechatBotCommandSuggestions(bobRoom, '!mo').map((c) => c.command),
          ['!modell'],
        );
      },
    );

    test('nothing is suggested in the middle of a message', () {
      expect(gruppechatBotCommandSuggestions(bobRoom, 'Hei !st'), isEmpty);
      expect(gruppechatBotCommandSuggestions(bobRoom, '!status '), isEmpty);
    });
  });
}

extension<T> on List<T> {
  List<T>? get nullIfEmpty => this.isEmpty ? null : this;
}
