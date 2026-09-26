// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/gruppechat/group_state.dart';
import 'package:fluffychat/gruppechat/matrix_group.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import '../utils/test_client.dart';

void main() {
  const admin = '@admin:example.invalid';
  const bob = '@bob:example.invalid';

  late Client client;
  late Room space;
  late Room channel;

  void setState(
    Room room,
    String type,
    String stateKey,
    Map<String, Object?> content,
  ) => room.setState(
    StrippedStateEvent(
      type: type,
      content: content,
      senderId: admin,
      stateKey: stateKey,
    ),
  );

  setUp(() async {
    client = await prepareTestClient();
    space = Room(id: '!space:example.invalid', client: client);
    channel = Room(id: '!channel:example.invalid', client: client);
    setState(space, EventTypes.RoomCreate, '', {
      'type': RoomCreationTypes.mSpace,
    });
    setState(space, EventTypes.SpaceChild, channel.id, {
      'via': ['example.invalid'],
    });
    client.rooms.add(space);
  });

  test('a space is its own group', () {
    expect(GruppechatGroup.of(space)?.space.id, space.id);
  });

  test('a channel finds its space through the space children', () {
    expect(GruppechatGroup.of(channel)?.space.id, space.id);
  });

  test('rooms outside any space have no group', () {
    final loose = Room(id: '!loose:example.invalid', client: client);
    expect(GruppechatGroup.of(loose), isNull);
  });

  test('reads state keys and senders from the room', () {
    setState(space, GruppechatEventTypes.role, 'admins', {'name': 'Admins'});
    final reader = RoomStateReader(space);
    expect(reader.stateKeys(GruppechatEventTypes.role), ['admins']);
    expect(reader.sender(GruppechatEventTypes.role, 'admins'), admin);
    expect(reader.stateKeys(GruppechatEventTypes.nickname), isEmpty);
  });

  test('users show their group nickname in every channel', () {
    setState(space, GruppechatEventTypes.nickname, userStateKey(bob), {
      'name': 'Captain',
    });
    expect(User(bob, room: channel).groupDisplayname(), 'Captain');
    expect(User(bob, room: space).groupDisplayname(), 'Captain');
  });

  test('users without a nickname keep their normal name', () {
    final user = User(bob, room: channel);
    expect(user.groupDisplayname(), user.calcDisplayname());
  });

  test('channels inherit and can override the group background', () {
    setState(space, GruppechatEventTypes.background, '', {
      'kind': 'solid',
      'colors': ['#1B1F3B'],
    });
    expect(channel.gruppechatBackground(enabled: true)?.colors, [
      0xFF1B1F3B,
    ]);
    expect(channel.gruppechatBackground(enabled: false), isNull);

    setState(channel, GruppechatEventTypes.background, '', {'kind': 'none'});
    expect(channel.gruppechatBackground(enabled: true), isNull);
    expect(space.gruppechatBackground(enabled: true)?.colors, [0xFF1B1F3B]);
  });

  test('role suggestions match the ID and the name', () {
    setState(space, GruppechatEventTypes.role, 'game-night', {
      'name': 'Game night',
    });
    setState(space, GruppechatEventTypes.role, 'quiet', {
      'name': 'Quiet',
      'mentionable': false,
    });
    final byId = gruppechatRoleSuggestions(channel, 'game');
    expect(byId.map((s) => s['mention']), ['@game-night']);
    expect(byId.single['type'], 'role');
    expect(gruppechatRoleSuggestions(channel, 'night').length, 1);
    expect(gruppechatRoleSuggestions(channel, 'quiet'), isEmpty);
  });

  test('group setup is needed until power levels cover the custom types', () {
    setState(space, EventTypes.RoomPowerLevels, '', {
      'users': {admin: 100},
    });
    final group = GruppechatGroup.of(space)!;
    expect(group.needsSetup, isTrue);
    setState(
      space,
      EventTypes.RoomPowerLevels,
      '',
      withGroupPowerLevels({
        'users': {admin: 100},
      }),
    );
    expect(group.needsSetup, isFalse);
  });
}
