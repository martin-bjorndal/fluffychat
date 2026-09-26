// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

import 'group_state.dart';

/// Reads group state straight from a room's state events.
class RoomStateReader implements GroupStateReader {
  final Room room;

  const RoomStateReader(this.room);

  @override
  Map<String, Object?>? content(String type, [String stateKey = '']) =>
      room.getState(type, stateKey)?.content;

  @override
  String? sender(String type, [String stateKey = '']) =>
      room.getState(type, stateKey)?.senderId;

  @override
  Iterable<String> stateKeys(String type) =>
      room.states[type]?.keys ?? const <String>[];
}

/// A group chat: a Matrix space whose rooms are its channels. All shared
/// data (roles, nicknames, background) lives in the space room's state.
class GruppechatGroup {
  final Room space;

  const GruppechatGroup(this.space);

  /// The group [room] belongs to: the room itself if it is a space,
  /// otherwise the first joined space that lists it as a child.
  static GruppechatGroup? of(Room room) {
    if (room.isSpace) return GruppechatGroup(room);
    final client = room.client;
    for (final parent in room.spaceParents) {
      final parentId = parent.roomId;
      if (parentId == null) continue;
      final space = client.getRoomById(parentId);
      if (space != null && _isJoinedSpace(space)) return GruppechatGroup(space);
    }
    for (final candidate in client.rooms) {
      if (_isJoinedSpace(candidate) &&
          candidate.spaceChildren.any((child) => child.roomId == room.id)) {
        return GruppechatGroup(candidate);
      }
    }
    return null;
  }

  static bool _isJoinedSpace(Room room) =>
      room.isSpace && room.membership == Membership.join;

  Client get _client => space.client;

  GroupState get state => GroupState(RoomStateReader(space));

  Map<String, Object?>? get _powerLevels =>
      space.getState(EventTypes.RoomPowerLevels)?.content;

  /// True until the space's power levels mention the custom event types.
  bool get needsSetup => !hasGroupPowerLevels(_powerLevels);

  bool get canSetUp => space.canChangePowerLevel;

  bool get canManageRoles =>
      space.canChangeStateEvent(GruppechatEventTypes.role) &&
      space.canChangeStateEvent(GruppechatEventTypes.memberRoles);

  bool get canSetNicknames =>
      space.canChangeStateEvent(GruppechatEventTypes.nickname);

  bool get canSetBackground =>
      space.canChangeStateEvent(GruppechatEventTypes.background);

  /// Adds the custom event types to the space's power levels.
  Future<void> setUp() async {
    final powerLevels = _powerLevels;
    if (powerLevels == null) {
      throw StateError('This group has no power levels to extend.');
    }
    await _client.setRoomStateWithKey(
      space.id,
      EventTypes.RoomPowerLevels,
      '',
      withGroupPowerLevels(powerLevels),
    );
  }

  /// Sets [userId]'s group-wide nickname. An empty [name] removes it.
  Future<void> setNickname(String userId, String name) =>
      _client.setRoomStateWithKey(
        space.id,
        GruppechatEventTypes.nickname,
        userStateKey(userId),
        name.trim().isEmpty
            ? <String, Object?>{}
            : GroupNickname.contentFor(name),
      );

  /// Stops (or allows) other people from renaming the current user. The
  /// state key is the user's own ID, so only they can change it.
  Future<void> setOwnNicknameLocked(bool locked) =>
      _client.setRoomStateWithKey(
        space.id,
        GruppechatEventTypes.nicknameLock,
        _client.userID!,
        {'locked': locked},
      );

  Future<String> createRole(String name) async {
    final id = roleIdFromName(
      name,
      RoomStateReader(space).stateKeys(GruppechatEventTypes.role),
    );
    await _client.setRoomStateWithKey(
      space.id,
      GruppechatEventTypes.role,
      id,
      GroupRole(id: id, name: name.trim()).toContent(),
    );
    return id;
  }

  Future<void> renameRole(GroupRole role, String name) =>
      _client.setRoomStateWithKey(
        space.id,
        GruppechatEventTypes.role,
        role.id,
        GroupRole(
          id: role.id,
          name: name.trim(),
          color: role.color,
          mentionable: role.mentionable,
        ).toContent(),
      );

  Future<void> deleteRole(String roleId) => _client.setRoomStateWithKey(
    space.id,
    GruppechatEventTypes.role,
    roleId,
    <String, Object?>{},
  );

  Future<void> setMemberRoles(String userId, Set<String> roleIds) =>
      _client.setRoomStateWithKey(
        space.id,
        GruppechatEventTypes.memberRoles,
        userStateKey(userId),
        {'roles': roleIds.toList()..sort()},
      );

  /// Sets the group background, or removes it when [background] is null.
  Future<void> setBackground(GroupBackground? background) =>
      _client.setRoomStateWithKey(
        space.id,
        GruppechatEventTypes.background,
        '',
        background?.toContent() ?? <String, Object?>{},
      );
}

extension GruppechatRoomExtension on Room {
  /// The shared background to draw in this room, or null for none.
  GroupBackground? gruppechatBackground({required bool enabled}) {
    final group = GruppechatGroup.of(this);
    if (group == null) return null;
    final channel = group.space.id == id
        ? null
        : GroupBackground.fromContent(
            getState(GruppechatEventTypes.background)?.content,
          );
    return resolveGroupBackground(
      channel: channel,
      group: group.state.background,
      enabled: enabled,
    );
  }
}

extension GruppechatUserExtension on User {
  /// Like [calcDisplayname], but prefers the group-wide nickname.
  String groupDisplayname({
    MatrixLocalizations i18n = const MatrixDefaultLocalizations(),
  }) =>
      GruppechatGroup.of(room)?.state.nicknameOf(id)?.displayName ??
      calcDisplayname(i18n: i18n);
}

extension GruppechatEventExtension on Event {
  /// Whether this message mentions a role the current user has.
  bool get mentionsOwnGroupRole {
    final userId = room.client.userID;
    if (userId == null || senderId == userId) return false;
    if (type != EventTypes.Message) return false;
    final state = GruppechatGroup.of(room)?.state;
    if (state == null) return false;
    return mentionsAnyRole(body, state.roles, state.roleIdsOf(userId));
  }
}

extension GruppechatClientExtension on Client {
  static const String _preferencesType = 'im.gruppechat.preferences';

  /// Whether group backgrounds are shown on this account's devices.
  bool get showGroupBackgrounds =>
      accountData[_preferencesType]?.content['show_group_backgrounds'] !=
      false;

  Future<void> setShowGroupBackgrounds(bool show) => setAccountData(
    userID!,
    _preferencesType,
    {'show_group_backgrounds': show},
  );
}

/// Input bar suggestions for `@role` mentions matching [search].
List<Map<String, String?>> gruppechatRoleSuggestions(
  Room room,
  String search,
) {
  final state = GruppechatGroup.of(room)?.state;
  if (state == null) return [];
  return [
    for (final role in state.roles)
      if (role.mentionable &&
          (role.id.contains(search) ||
              role.name.toLowerCase().contains(search)))
        {
          'type': 'role',
          'mention': '@${role.id}',
          'displayname': '@${role.id} · ${role.name}',
        },
  ];
}
