// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'matrix_group.dart';

/// Thrown when this user may not delete a chat after all.
class GruppechatCannotDeleteRoom implements Exception {
  final String roomId;
  const GruppechatCannotDeleteRoom(this.roomId);

  @override
  String toString() => 'Not allowed to delete $roomId';
}

/// The rooms [space] lists as its channels, or null when this user isn't
/// in one of them: what happens in that one is out of their reach.
List<Room>? _channels(Room space) {
  final channels = <Room>[];
  for (final child in space.spaceChildren) {
    final room = child.roomId == null
        ? null
        : space.client.getRoomById(child.roomId!);
    if (room == null || room.membership != Membership.join) return null;
    channels.add(room);
  }
  return channels;
}

/// The group space [room] is a channel of, if any.
Room? _parentSpace(Room room) {
  final space = GruppechatGroup.of(room)?.space;
  return space == null || space.id == room.id ? null : space;
}

/// [userId]'s level in [room] going by [powerLevels]. The creators of a
/// room of version 12 or later rank above everyone. As the SDK's
/// [Room.getPowerLevelByUserId], but for power levels fetched from the
/// server.
PowerLevel _levelOf(
  Room room,
  Map<String, Object?> powerLevels,
  String userId,
) {
  if (room.creatorUserIds.contains(userId) &&
      (int.tryParse(room.roomVersion ?? '') ?? 0) >= 12) {
    return PowerLevel.owner;
  }
  return PowerLevel(
    powerLevels.tryGetMap<String, Object?>('users')?.tryGet<int>(userId) ??
        powerLevels.tryGet<int>('users_default') ??
        0,
  );
}

/// Whether [userId] is in [room], invited or knocking, asked of the
/// server: this user's copy of the room doesn't always say who has left.
Future<bool> _isIn(Room room, String userId) async {
  try {
    final member = await room.client.getRoomStateWithKey(
      room.id,
      EventTypes.RoomMember,
      userId,
    );
    final membership = member.tryGet<String>('membership');
    return membership != Membership.leave.name &&
        membership != Membership.ban.name;
  } on MatrixException catch (e) {
    // Never been in it
    if (e.error == MatrixError.M_NOT_FOUND) return false;
    rethrow;
  }
}

/// Whether this user outranks everyone else who is in [room] or may get a
/// say in it, going by its [powerLevels], so the server lets them put
/// anyone out and nobody can stay behind in it. Those who have left don't
/// count: [_empty] closes the room before anyone is put out.
Future<bool> _outranksEveryone(
  Room room,
  Map<String, Object?> powerLevels,
) async {
  final own = _levelOf(room, powerLevels, room.client.userID!);
  if (PowerLevel(powerLevels.tryGet<int>('users_default') ?? 0) >= own) {
    return false;
  }
  final others = {
    ...?powerLevels.tryGetMap<String, Object?>('users')?.keys,
    ...room.creatorUserIds,
  }..remove(room.client.userID);
  for (final id in others) {
    if (_levelOf(room, powerLevels, id) < own) continue;
    if (await _isIn(room, id)) return false;
  }
  return true;
}

/// Whether this user may close [room] and put out anyone below them,
/// going by this user's copy of it.
bool _mayClose(Room room) {
  if (room.isDirectChat || room.membership != Membership.join) return false;
  final powerLevels = room.getState(EventTypes.RoomPowerLevels)?.content;
  // Closing it changes who may invite, which takes power levels to change
  if (powerLevels == null) return false;
  return room.canKick &&
      room.canChangePowerLevel &&
      (powerLevels.tryGet<int>('invite') ?? 0) <= room.ownPowerLevel.level &&
      room.canChangeStateEvent(EventTypes.RoomJoinRules);
}

/// Whether this user may delete [room] for everyone: a group chat, channel
/// or group (not a direct chat) in which they outrank everyone else still
/// in it. A channel also needs them to be allowed to take it out of its
/// group; a group needs them to be in all its channels, and allowed to
/// delete each. Asks the server only about those who rank as high as this
/// user, which is usually nobody.
Future<bool> gruppechatCanDeleteRoom(Room room) async {
  if (!_mayClose(room)) return false;
  final rooms = [room];
  if (room.isSpace) {
    final channels = _channels(room);
    if (channels == null ||
        !channels.every(_mayClose) ||
        !room.canChangeStateEvent(EventTypes.SpaceChild)) {
      return false;
    }
    rooms.addAll(channels);
  } else {
    final space = _parentSpace(room);
    if (space != null && !space.canChangeStateEvent(EventTypes.SpaceChild)) {
      return false;
    }
  }
  for (final each in rooms) {
    final powerLevels = each.getState(EventTypes.RoomPowerLevels)!.content;
    if (!await _outranksEveryone(each, powerLevels)) return false;
  }
  return true;
}

/// Deletes [room] for everyone. Matrix has no such thing for a room's
/// admin, so it is emptied: closed to new members, everyone else put out,
/// taken out of its group, and left. A group goes with all its channels.
/// [reason] is what the members are told.
///
/// A channel or member that fails doesn't stop the rest. A channel that
/// fails stays in the group, and the group stays with its members, so
/// running it again goes on from there; the first error is thrown at the
/// end. (Should leaving a channel fail after it was taken out of its group,
/// it is left behind, empty, for this user only, to delete on its own.)
Future<void> gruppechatDeleteRoom(Room room, {String? reason}) async {
  if (!await gruppechatCanDeleteRoom(room)) {
    throw GruppechatCannotDeleteRoom(room.id);
  }
  if (room.isSpace) {
    // A sync while the check waited on the server may have changed them
    final channels = _channels(room);
    if (channels == null) throw GruppechatCannotDeleteRoom(room.id);
    await _eachThenRethrowFirst(channels, (channel) async {
      await _empty(channel, reason);
      await room.removeSpaceChild(channel.id);
      await _leave(channel);
    }, (channel) => 'Could not delete channel ${channel.id}');
    await _empty(room, reason);
  } else {
    await _empty(room, reason);
    await _parentSpace(room)?.removeSpaceChild(room.id);
  }
  await _leave(room);
}

/// Closes [room]: only this user may invite and nobody may join without
/// an invite. Then everyone else is put out, as many as can be. Nothing is
/// done if the server's power levels show someone in it who ranks as high
/// as this user (made so on another device, say).
Future<void> _empty(Room room, String? reason) async {
  final powerLevels = await room.client.getRoomStateWithKey(
    room.id,
    EventTypes.RoomPowerLevels,
    '',
  );
  if (!await _outranksEveryone(room, powerLevels)) {
    throw GruppechatCannotDeleteRoom(room.id);
  }
  final own = _levelOf(room, powerLevels, room.client.userID!).level;
  if (powerLevels.tryGet<int>('invite') != own) {
    await room.client.setRoomStateWithKey(
      room.id,
      EventTypes.RoomPowerLevels,
      '',
      {...powerLevels, 'invite': own},
    );
  }
  // Not kept in memory for chats that weren't opened, so always set
  await room.setJoinRules(JoinRules.invite);
  // From the server: someone who just came in must go too
  final members = await room.requestParticipants(
    const [Membership.join, Membership.invite, Membership.knock],
    true,
    null,
    true,
  );
  await _eachThenRethrowFirst(
    members.where((user) => user.id != room.client.userID),
    (user) => room.client.kick(room.id, user.id, reason: reason),
    (user) => 'Could not put ${user.id} out of ${room.id}',
  );
}

/// Runs [action] on each of [items] in turn, going on past those that fail,
/// then throws the first error, if any.
Future<void> _eachThenRethrowFirst<T>(
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

Future<void> _leave(Room room) async {
  await room.leave();
  try {
    await room.forget();
  } catch (e, s) {
    // Already out of it, so it is gone from the chat list either way.
    Logs().w('Could not forget ${room.id}', e, s);
  }
}

/// The red "delete" line at the bottom of a chat's details, for those who
/// may delete it. Checked again when the state of the room or one of its
/// channels changes, and when tapped.
class GruppechatDeleteRoomTile extends StatefulWidget {
  final Room room;

  const GruppechatDeleteRoomTile({required this.room, super.key});

  @override
  State<GruppechatDeleteRoomTile> createState() =>
      _GruppechatDeleteRoomTileState();
}

class _GruppechatDeleteRoomTileState extends State<GruppechatDeleteRoomTile> {
  bool _canDelete = false;
  StreamSubscription<({String roomId, StrippedStateEvent state})>? _changes;
  // A check is under way, and another one is due when it is done
  bool _checking = false;
  bool _due = false;

  Room get room => widget.room;

  /// Whether [update] changes who is in, or who may do what in, this room
  /// or one of its channels.
  bool _concerns(({String roomId, StrippedStateEvent state}) update) {
    if (!const {
      EventTypes.RoomMember,
      EventTypes.RoomPowerLevels,
      EventTypes.RoomJoinRules,
      EventTypes.SpaceChild,
    }.contains(update.state.type)) {
      return false;
    }
    return update.roomId == room.id ||
        room.spaceChildren.any((child) => child.roomId == update.roomId);
  }

  /// Checks again: one check at a time, and once more after it at most,
  /// however many changes come in while it asks the server, so the last
  /// answer is always the latest.
  Future<void> _recheck() async {
    if (_checking) {
      _due = true;
      return;
    }
    _checking = true;
    do {
      _due = false;
      bool canDelete;
      try {
        canDelete = await gruppechatCanDeleteRoom(room);
      } catch (e, s) {
        Logs().w('Could not tell if ${room.id} may be deleted', e, s);
        canDelete = false;
      }
      if (mounted && !_due && canDelete != _canDelete) {
        setState(() => _canDelete = canDelete);
      }
    } while (_due && mounted);
    _checking = false;
  }

  void _watch() {
    _changes?.cancel();
    _changes = room.client.onRoomState.stream.where(_concerns).listen((_) {
      _recheck();
    });
    _recheck();
  }

  @override
  void initState() {
    super.initState();
    _watch();
  }

  @override
  void didUpdateWidget(GruppechatDeleteRoomTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room.id != room.id) _watch();
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_canDelete) return const SizedBox.shrink();
    final l10n = L10n.of(context);
    final color = Theme.of(context).colorScheme.error;
    return ListTile(
      iconColor: color,
      textColor: color,
      leading: const Icon(Icons.delete_forever_outlined),
      title: Text(
        room.isSpace ? l10n.gruppechatDeleteGroup : l10n.gruppechatDeleteChat,
      ),
      onTap: () => _delete(context),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final l10n = L10n.of(context);
    final router = GoRouter.of(context);
    final confirmed = await showOkCancelAlertDialog(
      context: context,
      title: room.isSpace
          ? l10n.gruppechatDeleteGroup
          : l10n.gruppechatDeleteChat,
      message: room.isSpace
          ? l10n.gruppechatDeleteGroupDescription
          : l10n.gruppechatDeleteChatDescription,
      okLabel: l10n.delete,
      cancelLabel: l10n.cancel,
      isDestructive: true,
    );
    if (confirmed != OkCancelResult.ok || !context.mounted) return;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () async {
        try {
          await gruppechatDeleteRoom(
            room,
            reason: l10n.gruppechatChatWasDeleted,
          );
        } on GruppechatCannotDeleteRoom {
          // Someone ranks as high as this user after all
          throw l10n.noPermission;
        }
      },
    );
    if (result.error == null) {
      router.go('/rooms');
    } else {
      _recheck();
    }
  }
}
