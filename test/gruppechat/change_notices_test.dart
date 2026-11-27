// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// How a line saying who changed a background, colour or nickname reads
// (lib/gruppechat/change_notices.dart).

import 'package:fluffychat/gruppechat/change_notices.dart';
import 'package:fluffychat/gruppechat/matrix_group.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import '../utils/test_client.dart';

void main() {
  late Client client;
  late Room room;
  late L10n l10n;
  const bob = '@bob:example.invalid';
  const carol = '@carol:example.invalid';

  setUpAll(() async {
    client = await prepareTestClient(loggedIn: true);
    room = Room(id: '!chat:example.invalid', client: client);
    l10n = await lookupL10n(const Locale('nb'));
  });

  Event line(String sender, Map<String, Object?> content) => Event(
    type: gruppechatChangeType,
    content: content,
    senderId: sender,
    eventId: '\$${content.hashCode}',
    originServerTs: DateTime(2026, 11, 12),
    room: room,
  );
  String nameOf(String userId) =>
      room.unsafeGetUserFromMemoryOrFallback(userId).calcDisplayname();
  String? text(String sender, Map<String, Object?> content) =>
      groupChangeText(line(sender, content), l10n);

  test('backgrounds and colours name who changed them', () {
    expect(
      text(bob, {'kind': 'group_background'}),
      l10n.gruppechatChangedGroupBackground(nameOf(bob)),
    );
    expect(text(bob, {'kind': 'group_background'}), contains('gruppen'));
    expect(
      text(bob, {'kind': 'chat_background'}),
      l10n.gruppechatChangedChatBackground(nameOf(bob)),
    );
    expect(
      text(bob, {'kind': 'chat_color'}),
      l10n.gruppechatChangedChatColor(nameOf(bob)),
    );
  });

  test('a nickname, for someone else or oneself', () {
    expect(
      text(bob, {'kind': 'nickname', 'user': carol, 'nickname': 'Kaptein'}),
      l10n.gruppechatGaveNickname(nameOf(bob), nameOf(carol), 'Kaptein'),
    );
    expect(
      text(bob, {'kind': 'nickname', 'user': carol}),
      l10n.gruppechatRemovedNickname(nameOf(bob), nameOf(carol)),
    );
    expect(
      text(carol, {'kind': 'nickname', 'user': carol, 'nickname': 'Kaptein'}),
      l10n.gruppechatTookNickname(nameOf(carol), 'Kaptein'),
    );
    expect(
      text(carol, {'kind': 'nickname', 'user': carol}),
      l10n.gruppechatDroppedNickname(nameOf(carol)),
    );
  });

  test('a picture in the group, for someone else or oneself', () {
    expect(
      text(bob, {'kind': 'avatar', 'user': carol}),
      l10n.gruppechatGaveGroupPicture(nameOf(bob), nameOf(carol)),
    );
    expect(
      text(bob, {'kind': 'avatar', 'user': carol, 'removed': true}),
      l10n.gruppechatRemovedGroupPicture(nameOf(bob), nameOf(carol)),
    );
    expect(
      text(carol, {'kind': 'avatar', 'user': carol}),
      l10n.gruppechatTookGroupPicture(nameOf(carol)),
    );
    expect(
      text(carol, {'kind': 'avatar', 'user': carol, 'removed': true}),
      l10n.gruppechatDroppedGroupPicture(nameOf(carol)),
    );
    expect(text(bob, {'kind': 'avatar'}), isNull, reason: 'whose is missing');
  });

  test('a line this version does not understand shows nothing of its own', () {
    expect(text(bob, {'kind': 'something_new'}), isNull);
    expect(text(bob, {'kind': 'nickname'}), isNull);
    final long = 'x' * 500;
    expect(
      text(bob, {'kind': 'nickname', 'user': carol, 'nickname': long}),
      isNot(contains(long)),
    );
    expect(isGroupChangeLine(line(bob, {'kind': 'something_new'})), isFalse);
    expect(isGroupChangeLine(line(bob, {'kind': 'nickname'})), isFalse);
    expect(isGroupChangeLine(line(bob, {'kind': 'chat_color'})), isTrue);
  });

  test('a long nickname of emoji is cut between them, not inside one', () {
    final shown = text(bob, {
      'kind': 'nickname',
      'user': carol,
      'nickname': 'a${'😀' * 100}',
    })!;
    expect(shown, contains('a${'😀' * 63}…'));
    expect(shown, isNot(contains('😀' * 64)));
  });

  test('it shows in the chat and does not fold away', () {
    final event = line(bob, {'kind': 'chat_color'});
    expect(event.isState, isTrue, reason: 'drawn as a state line');
    expect(event.isCollapsedState, isFalse);
  });

  group('pinning', () {
    Event pins(
      List<String> now, {
      List<String>? before,
      bool redacted = false,
    }) => Event(
      type: EventTypes.RoomPinnedEvents,
      content: {'pinned': now},
      senderId: bob,
      stateKey: '',
      eventId: '\$pin${now.join()}${before?.join()}',
      originServerTs: DateTime(2026, 11, 27),
      room: room,
      unsigned: {
        if (before != null) 'prev_content': {'pinned': before},
        if (redacted)
          'redacted_because': {
            'type': EventTypes.Redaction,
            'event_id': r'$redaction',
            'sender': bob,
            'origin_server_ts': 0,
            'content': <String, Object?>{},
          },
      },
    );

    test('a pin and an unpin name who did it', () {
      expect(
        groupChangeText(pins([r'$a']), l10n),
        l10n.gruppechatPinnedMessage(nameOf(bob)),
        reason: 'the first pin has no list before it',
      );
      expect(
        groupChangeText(pins([r'$a', r'$b'], before: [r'$a']), l10n),
        l10n.gruppechatPinnedMessage(nameOf(bob)),
      );
      expect(
        groupChangeText(pins([r'$a'], before: [r'$a', r'$b']), l10n),
        l10n.gruppechatUnpinnedMessage(nameOf(bob)),
      );
      expect(
        groupChangeText(pins([], before: [r'$a']), l10n),
        l10n.gruppechatUnpinnedMessage(nameOf(bob)),
      );
      expect(pinChangeOf(pins([r'$b'], before: [r'$a'])), PinChange.pinned);
    });

    test('a pin shows in the chat and does not fold away', () {
      final event = pins([r'$a'], before: []);
      expect(isGroupChangeLine(event), isTrue);
      expect(event.isVisibleInGui, isTrue);
      expect(event.isCollapsedState, isFalse);
    });

    test('a list that changed nothing, or was deleted, says nothing', () {
      for (final event in [
        pins([r'$a', r'$b'], before: [r'$b', r'$a']),
        pins([]),
        pins([r'$a'], before: [], redacted: true),
      ]) {
        expect(groupChangeText(event, l10n), isNull);
        expect(isGroupChangeLine(event), isFalse);
        expect(event.isCollapsedState, isTrue);
      }
    });

    test('a list that is no list is no pin, and breaks nothing', () {
      final odd = Event(
        type: EventTypes.RoomPinnedEvents,
        content: {'pinned': r'$a'},
        senderId: bob,
        stateKey: '',
        eventId: r'$odd',
        originServerTs: DateTime(2026, 11, 27),
        room: room,
        unsigned: {
          'prev_content': {'pinned': <String, Object?>{}},
        },
      );
      expect(pinChangeOf(odd), isNull);
      expect(groupChangeText(odd, l10n), isNull);
      expect(odd.isCollapsedState, isTrue);
    });
  });

  test("a space's background is the group's, a chat's its own", () {
    final space = Room(id: '!space:example.invalid', client: client)
      ..setState(
        StrippedStateEvent(
          type: EventTypes.RoomCreate,
          content: {'type': RoomCreationTypes.mSpace},
          senderId: bob,
          stateKey: '',
        ),
      );
    final channel = Room(id: '!channel:example.invalid', client: client);
    expect(
      backgroundChangeFor(GruppechatGroup(space), null),
      GroupChange.groupBackground,
    );
    expect(
      backgroundChangeFor(GruppechatGroup(space), channel),
      GroupChange.chatBackground,
    );
    expect(
      backgroundChangeFor(GruppechatGroup(channel), null),
      GroupChange.chatBackground,
    );
  });

  test(
    "a change from the group's member list is told in its first channel",
    () {
      final space = Room(id: '!group:example.invalid', client: client)
        ..setState(
          StrippedStateEvent(
            type: EventTypes.RoomCreate,
            content: {'type': RoomCreationTypes.mSpace},
            senderId: bob,
            stateKey: '',
          ),
        );
      final group = GruppechatGroup(space);
      final added = <String>{};
      addTearDown(() => client.rooms.removeWhere((r) => added.contains(r.id)));
      Room channel(String id, {String? order, int ts = 0, bool may = true}) {
        space.setState(
          Event(
            type: EventTypes.SpaceChild,
            content: {
              'via': ['example.invalid'],
              'order': ?order,
            },
            senderId: bob,
            stateKey: id,
            eventId: '\$child$id',
            originServerTs: DateTime.fromMillisecondsSinceEpoch(ts),
            room: space,
          ),
        );
        final room = Room(id: id, client: client, membership: Membership.join);
        if (!may) {
          room.setState(
            StrippedStateEvent(
              type: EventTypes.RoomPowerLevels,
              content: {'events_default': 100},
              senderId: bob,
              stateKey: '',
            ),
          );
        }
        client.rooms.add(room);
        added.add(id);
        return room;
      }

      final general = channel('!d:example.invalid', ts: 1);
      final older = channel('!c:example.invalid', ts: 1);
      expect(
        changeLineChatFor(group, space),
        older,
        reason: 'the oldest, then by room ID',
      );
      final ordered = channel('!z:example.invalid', order: 'b', ts: 9);
      channel('!y:example.invalid', order: 'a', ts: 9, may: false);
      // Too long to count as an order
      channel('!x:example.invalid', order: '0' * 51, ts: 9);
      // A space inside the group is no chat
      channel(
        '!w:example.invalid',
        order: '0',
        ts: 9,
      ).setState(space.getState(EventTypes.RoomCreate)!);
      expect(
        changeLineChatFor(group, space),
        ordered,
        reason: 'by order first, where the line may be posted',
      );
      expect(changeLineChatFor(group, general), general, reason: 'a channel');
      expect(changeLineChatFor(group, null), isNull);
      final otherSpace = Room(id: '!other:example.invalid', client: client)
        ..setState(space.getState(EventTypes.RoomCreate)!);
      expect(
        changeLineChatFor(group, otherSpace),
        otherSpace,
        reason: "only the group's own space",
      );
    },
  );
}
