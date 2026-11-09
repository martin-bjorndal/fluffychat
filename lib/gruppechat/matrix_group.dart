// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

import 'group_state.dart';

/// State the app keeps in memory even for rooms that were never opened: our
/// event types, plus the power levels every permission check depends on. The
/// SDK doesn't keep power levels loaded by default, so without this a group
/// whose space room was never opened can't even be set up.
const Set<String> gruppechatImportantStateEvents = {
  ...GruppechatEventTypes.all,
  EventTypes.RoomPowerLevels,
};

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

/// A group chat: a Matrix space whose rooms are its channels, or a single
/// group chat that isn't in a space. All shared data (roles, nicknames,
/// background) lives in the state of [space].
class GruppechatGroup {
  /// The room holding the group's shared state: the space, or the chat
  /// itself when it isn't in a space.
  final Room space;

  const GruppechatGroup(this.space);

  /// The group [room] belongs to: the room itself if it is a space,
  /// otherwise the first joined space that lists it as a child. A group chat
  /// outside any space is its own group. Direct chats, and channels of a
  /// space the user hasn't joined, have no group.
  static GruppechatGroup? of(Room room) {
    if (room.isSpace) return GruppechatGroup(room);
    final client = room.client;
    final parents = room.spaceParents;
    for (final parent in parents) {
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
    if (parents.isNotEmpty || room.isDirectChat) return null;
    return GruppechatGroup(room);
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

  bool get canSetChatColor =>
      space.canChangeStateEvent(GruppechatEventTypes.chatColor);

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

  static final Set<String> _setUpTried = {};

  /// Sets up group features the first time someone who may do it opens one
  /// of the group's chats, so the defaults apply: everyone can set
  /// nicknames and backgrounds, moderators manage roles. Groups made before
  /// group features existed only let moderators do any of it. Tried once
  /// per group while the app runs.
  Future<void> setUpIfNeeded() async {
    if (!needsSetup || !canSetUp || !_setUpTried.add(space.id)) return;
    try {
      await setUp();
    } catch (e, s) {
      Logs().w('Could not set up group features in ${space.id}', e, s);
    }
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
  Future<void> setOwnNicknameLocked(bool locked) => _client.setRoomStateWithKey(
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

  /// Sets [channel]'s own background, which overrides the group's there.
  /// Null shows the group's background in the channel again. It is kept in
  /// the space, keyed by the channel's room ID, so everyone who may set the
  /// group's background may set it: channels only let moderators send it.
  Future<void> setChannelBackground(
    Room channel,
    GroupBackground? background,
  ) => _client.setRoomStateWithKey(
    space.id,
    GruppechatEventTypes.background,
    channel.id,
    background?.toContent() ?? <String, Object?>{},
  );

  /// Sets [chat]'s own colour for its bars and bubbles, or removes it when
  /// [color] is null. Like a channel's background, it is kept here, keyed by
  /// the chat's room ID; for a direct chat, the chat is its own group.
  Future<void> setChatColor(Room chat, int? color) =>
      _client.setRoomStateWithKey(
        space.id,
        GruppechatEventTypes.chatColor,
        chat.id,
        color == null ? <String, Object?>{} : {'color': formatHexColor(color)},
      );

  /// Sets the group background, or removes it when [background] is null.
  Future<void> setBackground(GroupBackground? background) =>
      _client.setRoomStateWithKey(
        space.id,
        GruppechatEventTypes.background,
        '',
        background?.toContent() ?? <String, Object?>{},
      );

  /// Invites everyone with [roleId] who isn't in [channel] yet, and returns
  /// their user IDs. Banned members are left out.
  Future<List<String>> inviteRole(Room channel, String roleId) async {
    final present = {
      for (final user in await channel.requestParticipants([
        Membership.join,
        Membership.invite,
        Membership.ban,
      ]))
        user.id,
    };
    final invitees = [
      for (final userId in state.membersWithRole(roleId))
        if (!present.contains(userId)) userId,
    ];
    for (final userId in invitees) {
      await channel.invite(userId);
    }
    return invitees;
  }
}

extension GruppechatRoomExtension on Room {
  /// Where the background shown in this room is set: its group, or for a
  /// direct chat, which has no group, the chat itself.
  GruppechatGroup? get gruppechatBackgroundGroup =>
      GruppechatGroup.of(this) ?? (isDirectChat ? GruppechatGroup(this) : null);

  /// The background this channel sets for itself, overriding the group's;
  /// see [GruppechatGroup.setChannelBackground]. Older versions kept it in
  /// the channel itself, which counts until the group says otherwise.
  GroupBackground? get gruppechatChannelBackground {
    final group = GruppechatGroup.of(this);
    if (group == null || group.space.id == id) return null;
    final inGroup = group.space.getState(GruppechatEventTypes.background, id);
    return GroupBackground.fromContent(
      (inGroup ?? getState(GruppechatEventTypes.background))?.content,
    );
  }

  /// The colour this chat's bars and bubbles take, or null for the app's
  /// own; see [GruppechatGroup.setChatColor].
  int? get gruppechatChatColor => parseChatColor(
    gruppechatBackgroundGroup?.space
        .getState(GruppechatEventTypes.chatColor, id)
        ?.content,
  );

  /// The shared background to draw in this room, or null for none.
  GroupBackground? gruppechatBackground({required bool enabled}) {
    final group = gruppechatBackgroundGroup;
    if (group == null) return null;
    return resolveGroupBackground(
      channel: gruppechatChannelBackground,
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
      accountData[_preferencesType]?.content['show_group_backgrounds'] != false;

  Future<void> setShowGroupBackgrounds(bool show) => setAccountData(
    userID!,
    _preferencesType,
    {'show_group_backgrounds': show},
  );
}

/// Input bar suggestions for `@role` mentions matching [search].
List<Map<String, String?>> gruppechatRoleSuggestions(Room room, String search) {
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
