// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Wish from 1.1.44 (Synnøve, Martin): `:)` and `:(` sent in a chat become 🙂
// and 🙁, and a group's moderators keep their own list of words that become
// something else, for everyone in the group. How it feels with a phone's own
// keyboard can only be tried on a phone.

@Timeout(Duration(minutes: 3))
library;

import 'package:fluffychat/gruppechat/matrix_group.dart';
import 'package:fluffychat/gruppechat/new_chat_power_levels.dart';
import 'package:fluffychat/gruppechat/text_replacements.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'utils/test_server.dart';

/// What [text] becomes when typed key by key into the chat's input field in
/// [room], and then sent.
String typedAndSent(Room room, String text) {
  final replacer = GruppechatTextReplacer(
    () => room.gruppechatTextReplacements,
  );
  var value = TextEditingValue.empty;
  for (final char in text.split('')) {
    final typed = value.text + char;
    value = replacer.formatEditUpdate(
      value,
      TextEditingValue(
        text: typed,
        selection: TextSelection.collapsed(offset: typed.length),
      ),
    );
  }
  return replacer.onSend(value.text);
}

void main() {
  group('Text replacements', skip: skipWithoutTestServer, () {
    late Client alice;
    late Client bob;

    setUpAll(() async {
      alice = await logIn('alice');
      bob = await logIn('bob');
    });
    tearDownAll(logOutEveryone);

    test('in a direct chat, :) and :( become 🙂 and 🙁', () async {
      final (aliceChat, bobChat) = await directChat(alice, bob);
      final text = typedAndSent(bobChat, 'hei :) men :(');
      expect(text, 'hei 🙂 men 🙁');
      await bobChat.sendTextEvent(text);
      final received = await arrives(
        await aliceChat.getTimeline(),
        "bob's message",
        (e) => e.senderId == bob.userID && e.type == EventTypes.Message,
      );
      expect(received.body, 'hei 🙂 men 🙁');
    });

    test('alice gives her group its own list, bob\'s typing follows it, and '
        'bob can\'t change it', () async {
      final made = await newGroup(alice, [bob]);
      final aliceGroup = GruppechatGroup(alice.getRoomById(made.spaceId)!);
      expect(aliceGroup.canSetTextReplacements, isTrue);
      await aliceGroup.setTextReplacements(
        withTextReplacement(
          aliceGroup.textReplacements,
          const TextReplacement('mvh', 'med vennleg helsing'),
        ),
      );

      final bobChannel = bob.getRoomById(made.firstChannel)!;
      await eventually(
        'bob\'s channel has the group\'s list',
        () => bobChannel.gruppechatTextReplacements.any(
          (rule) => rule.from == 'mvh',
        ),
      );
      final text = typedAndSent(bobChannel, 'Mvh bob :)');
      expect(text, 'med vennleg helsing bob 🙂');
      await bobChannel.sendTextEvent(text);
      final received = await arrives(
        await alice.getRoomById(made.firstChannel)!.getTimeline(),
        "bob's message",
        (e) => e.senderId == bob.userID && e.type == EventTypes.Message,
      );
      expect(received.body, 'med vennleg helsing bob 🙂');

      final bobGroup = GruppechatGroup.of(bobChannel)!;
      expect(bobGroup.canSetTextReplacements, isFalse);
      expect(
        await isForbidden(() => bobGroup.setTextReplacements(null)),
        isTrue,
      );

      // Alice goes back to the standard list
      await aliceGroup.setTextReplacements(null);
      await eventually(
        'bob\'s channel is back to the standard list',
        () => !bobChannel.gruppechatTextReplacements.any(
          (rule) => rule.from == 'mvh',
        ),
      );
      expect(typedAndSent(bobChannel, 'mvh :)'), 'mvh 🙂');
    });

    test('in a group chat outside a space, only moderators change the list, '
        'and a list set by anyone else doesn\'t count', () async {
      final roomId = await alice.createGroupChat(
        visibility: Visibility.private,
        preset: CreateRoomPreset.privateChat,
        groupName: 'Utan gruppe',
        powerLevelContentOverride: newChatPowerLevels(),
        initialState: [],
      );
      await alice.getRoomById(roomId)!.invite(bob.userID!);
      final bobChat = await accept(bob, roomId);
      await seesMembers(bobChat, [alice.userID!, bob.userID!]);
      final bobGroup = GruppechatGroup.of(bobChat)!;
      expect(bobGroup.space.id, roomId);
      expect(bobGroup.canSetTextReplacements, isFalse);
      expect(
        await isForbidden(
          () =>
              bobGroup.setTextReplacements(const [TextReplacement(':)', '💩')]),
        ),
        isTrue,
      );

      // A chat from before the list existed, where everyone may set it on
      // the server: bob's list is ignored
      final oldId = await alice.createGroupChat(
        visibility: Visibility.private,
        preset: CreateRoomPreset.privateChat,
        groupName: 'Gammal',
        powerLevelContentOverride: {
          ...newChatPowerLevels(),
          'events': {
            ...(newChatPowerLevels()['events'] as Map)
              ..remove(gruppechatTextReplacementsType),
          },
        },
        initialState: [],
      );
      await alice.getRoomById(oldId)!.invite(bob.userID!);
      final bobOld = await accept(bob, oldId);
      await seesMembers(bobOld, [alice.userID!, bob.userID!]);
      final oldGroup = GruppechatGroup.of(bobOld)!;
      expect(oldGroup.canSetTextReplacements, isFalse);
      await oldGroup.setTextReplacements(const [TextReplacement(':)', '💩')]);
      final aliceOld = alice.getRoomById(oldId)!;
      await eventually(
        'alice sees bob\'s list arrive',
        () => aliceOld.getState(gruppechatTextReplacementsType) != null,
      );
      expect(aliceOld.gruppechatTextReplacements, defaultTextReplacements);
      expect(typedAndSent(aliceOld, ':)'), '🙂');
    });

    test('a list can never make someone run a command, nor reach into a '
        'direct chat from a space', () async {
      final made = await newGroup(alice, [bob]);
      final space = alice.getRoomById(made.spaceId)!;
      // Alice, a moderator, writes the list by hand, past the app's checks
      await alice.setRoomStateWithKey(
        made.spaceId,
        gruppechatTextReplacementsType,
        '',
        {
          'replacements': [
            {'from': 'ok', 'to': '/leave'},
            {'from': 'ja', 'to': ' /op @alice:localhost 100'},
            {'from': 'mvh', 'to': 'med vennleg helsing'},
          ],
        },
      );
      final bobChannel = bob.getRoomById(made.firstChannel)!;
      await eventually(
        'bob\'s channel has the group\'s list',
        () => bobChannel.gruppechatTextReplacements.any(
          (rule) => rule.from == 'mvh',
        ),
      );
      expect(typedAndSent(bobChannel, 'ok'), 'ok');
      expect(typedAndSent(bobChannel, 'ja takk'), 'ja takk');
      // And should a command come out anyway, only a typed one runs
      expect(gruppechatMayRunCommand('ok', '/leave'), isFalse);
      expect(gruppechatMayRunCommand('/me ler', '/me ler 🙂'), isTrue);
      expect(gruppechatMayRunCommand('hei', 'hei 🙂'), isTrue);

      // Alice lists her direct chat with bob in her space; bob's direct
      // chat keeps the standard list
      final (aliceChat, bobChat) = await directChat(alice, bob);
      await space.setSpaceChild(aliceChat.id);
      await eventually(
        'bob sees the direct chat in the space',
        () => bob
            .getRoomById(made.spaceId)!
            .spaceChildren
            .any((child) => child.roomId == bobChat.id),
      );
      expect(bobChat.gruppechatTextReplacements, defaultTextReplacements);
      expect(typedAndSent(bobChat, 'mvh :)'), 'mvh 🙂');
    });
  });
}
