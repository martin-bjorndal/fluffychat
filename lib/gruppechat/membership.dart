// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:matrix/matrix.dart';

/// The room a chat page that was opened on [opened] shows, as [client]
/// knows it now.
///
/// Someone who is kicked or banned drops the room from their client, but the
/// open page and its messages keep the old [Room], which still says joined,
/// so the field for writing stayed. This marks that room as left, so that
/// everything asking it whether the user may write, react or reply says no.
Room gruppechatChatRoom(Client client, Room opened) {
  final current = client.getRoomById(opened.id);
  if (current != null) return current;
  if (opened.membership == Membership.join &&
      opened.client.getRoomById(opened.id) == null) {
    opened.membership = Membership.leave;
  }
  return opened;
}

/// Leaves [room], as "Leave" in the chat's menus does.
///
/// Someone kicked or banned is out already, and the server refuses to let
/// them leave again, which showed as "no access". When the server's list of
/// rooms they are in no longer has it, that counts as left: the room stays
/// in the archive, as the question before leaving says. Any other refusal
/// still shows.
Future<void> gruppechatLeaveRoom(Room room) async {
  try {
    await room.leave();
  } on MatrixException catch (e, s) {
    if (e.error != MatrixError.M_FORBIDDEN) rethrow;
    try {
      if (!(await room.client.getJoinedRooms()).contains(room.id)) return;
    } catch (checkError, checkStack) {
      Logs().w(
        'Could not check whether ${room.id} was left',
        checkError,
        checkStack,
      );
    }
    Error.throwWithStackTrace(e, s);
  }
}

/// [userId]'s membership in [room] (`join`, `leave`, `ban`...), asked of
/// the server, or null if they have never been in it. An event that doesn't
/// say gives "". This user's copy of
/// a room doesn't always say who has left, and holds no members at all for
/// a chat that wasn't opened.
Future<String?> gruppechatMembershipOnServer(Room room, String userId) async {
  try {
    final member = await room.client.getRoomStateWithKey(
      room.id,
      EventTypes.RoomMember,
      userId,
    );
    return member.tryGet<String>('membership') ?? '';
  } on MatrixException catch (e) {
    if (e.error == MatrixError.M_NOT_FOUND) return null;
    rethrow;
  }
}

/// Runs [action] on each of [items] in turn, going on past those that fail,
/// then throws the first error, if any.
Future<void> gruppechatEachThenRethrowFirst<T>(
  Iterable<T> items,
  Future<void> Function(T) action,
  String Function(T) describe,
) async {
  (Object, StackTrace)? failure;
  for (final item in items) {
    try {
      await action(item);
    } catch (e, s) {
      Logs().w(describe(item), e, s);
      failure ??= (e, s);
    }
  }
  if (failure != null) Error.throwWithStackTrace(failure.$1, failure.$2);
}

/// The rooms [space] lists as its channels: those this user is in, and
/// those out of their reach. Of these nothing is known, not even a name.
({List<Room> channels, List<Room> outOfReach}) gruppechatChannelsOf(
  Room space,
) {
  final client = space.client;
  final channels = <Room>[];
  final outOfReach = <Room>[];
  for (final child in space.spaceChildren) {
    final roomId = child.roomId;
    if (roomId == null) continue;
    final room = client.getRoomById(roomId);
    if (room == null || room.membership != Membership.join) {
      outOfReach.add(room ?? Room(id: roomId, client: client));
    } else {
      channels.add(room);
    }
  }
  return (channels: channels, outOfReach: outOfReach);
}

/// Thrown when someone was put out of a group, or let back in, but this
/// user couldn't do the same in [channels]: they aren't in them, or may not
/// do it there.
class GruppechatStillInChannels implements Exception {
  final List<Room> channels;
  const GruppechatStillInChannels(this.channels);

  @override
  String toString() =>
      'Not done in ${channels.map((room) => room.id).join(', ')}';
}

/// Kicks [user] out of their room, as "Kick" in the member list does. In a
/// group's own member list that means the group and all its channels, or
/// they could go on writing in the channels.
Future<void> gruppechatKick(User user) => _inGroup(
  user,
  (room) => room.canKick,
  (membership) => const {'join', 'invite', 'knock'}.contains(membership),
  (room) => room.kick(user.id),
);

/// Bans [user] from their room; in a group's own member list, from the
/// group and all its channels, also those they aren't in.
Future<void> gruppechatBan(User user) => _inGroup(
  user,
  (room) => room.canBan,
  (membership) => membership != Membership.ban.name,
  (room) => room.ban(user.id),
);

/// Lifts the ban on [user]; in a group's own member list, in the group and
/// every channel they are banned from, so they can be invited back.
Future<void> gruppechatUnban(User user) => _inGroup(
  user,
  (room) => room.canBan,
  (membership) => membership == Membership.ban.name,
  (room) => room.unban(user.id),
);

/// Does [action] in [user]'s room. When that is a group's space, it is done
/// first in each of its channels where [needed] says so of [user]'s
/// membership there (asked of the server). The space comes last, and only
/// if every channel went through, so that it can be tried again from the
/// space's member list. Channels this user isn't in, or where [may] says
/// no or they don't outrank [user], are left as they are and named in a
/// [GruppechatStillInChannels] at the end.
Future<void> _inGroup(
  User user,
  bool Function(Room room) may,
  bool Function(String? membership) needed,
  Future<void> Function(Room room) action,
) async {
  final space = user.room;
  if (!space.isSpace) return action(space);
  final (:channels, :outOfReach) = gruppechatChannelsOf(space);
  final notDone = [...outOfReach];
  await gruppechatEachThenRethrowFirst(channels, (channel) async {
    if (!needed(await gruppechatMembershipOnServer(channel, user.id))) {
      return;
    }
    if (!may(channel) ||
        channel.getPowerLevelByUserId(user.id) >= channel.ownPowerLevel) {
      notDone.add(channel);
      return;
    }
    await action(channel);
  }, (channel) => 'Could not do it for ${user.id} in ${channel.id}');
  await action(space);
  if (notDone.isNotEmpty) throw GruppechatStillInChannels(notDone);
}

/// Waits for [done] (one of the above), turning [GruppechatStillInChannels]
/// into what the member menu shows.
Future<void> gruppechatTellingNotDone(L10n l10n, Future<void> done) async {
  try {
    await done;
  } on GruppechatStillInChannels catch (e) {
    throw l10n.gruppechatNotDoneInChannels(e.channels.length);
  }
}
