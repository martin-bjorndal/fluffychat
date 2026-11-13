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
}
