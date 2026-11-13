// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

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

/// Whether this user outranks everyone else who has or may get a say in
/// [room], going by its [powerLevels], so the server lets them put anyone
/// out and nobody can stay behind in it.
bool _outranksEveryone(Room room, Map<String, Object?> powerLevels) {
  final own = room.ownPowerLevel;
  final others = {
    ...?powerLevels.tryGetMap<String, Object?>('users')?.keys,
    ...room.creatorUserIds,
  }..remove(room.client.userID);
  if (others.any((id) => room.getPowerLevelByUserId(id) >= own)) {
    return false;
  }
  return PowerLevel(powerLevels.tryGet<int>('users_default') ?? 0) < own;
}

/// Whether this user may close [room] and put everyone else out of it.
bool _mayEmpty(Room room) {
  if (room.isDirectChat || room.membership != Membership.join) return false;
  final powerLevels = room.getState(EventTypes.RoomPowerLevels)?.content;
  // Closing it changes who may invite, which takes power levels to change
  if (powerLevels == null) return false;
  return room.canKick &&
      room.canChangePowerLevel &&
      (powerLevels.tryGet<int>('invite') ?? 0) <= room.ownPowerLevel.level &&
      room.canChangeStateEvent(EventTypes.RoomJoinRules) &&
      _outranksEveryone(room, powerLevels);
}

/// Whether this user may delete [room] for everyone: a group chat, channel
/// or group (not a direct chat) in which they outrank everyone else. A
/// channel also needs them to be allowed to take it out of its group; a
/// group needs them to be in all its channels, and allowed to delete each.
bool gruppechatCanDeleteRoom(Room room) {
  if (!_mayEmpty(room)) return false;
  if (room.isSpace) {
    final channels = _channels(room);
    return channels != null &&
        channels.every(_mayEmpty) &&
        room.canChangeStateEvent(EventTypes.SpaceChild);
  }
  final space = _parentSpace(room);
  return space == null || space.canChangeStateEvent(EventTypes.SpaceChild);
}

/// Deletes [room] for everyone. Matrix has no such thing for a room's
/// admin, so it is emptied: closed to new members, everyone else put out,
/// taken out of its group, and left. A group goes with all its channels.
/// [reason] is what the members are told.
///
/// It stops at the first thing that fails, with the room still there for
/// this user, and running it again goes on from there. (A channel already
/// taken out of its group is then left behind, empty, for this user only.)
Future<void> gruppechatDeleteRoom(Room room, {String? reason}) async {
  if (!gruppechatCanDeleteRoom(room)) {
    throw GruppechatCannotDeleteRoom(room.id);
  }
  if (room.isSpace) {
    for (final channel in _channels(room)!) {
      await _empty(channel, reason);
      await room.removeSpaceChild(channel.id);
      await _leave(channel);
    }
    await _empty(room, reason);
  } else {
    await _empty(room, reason);
    await _parentSpace(room)?.removeSpaceChild(room.id);
  }
  await _leave(room);
}

/// Closes [room]: only this user may invite and nobody may join without
/// an invite. Then everyone else is put out.
Future<void> _empty(Room room, String? reason) async {
  final own = room.ownPowerLevel.level;
  final powerLevels = room.getState(EventTypes.RoomPowerLevels)!.content;
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
  for (final user in members) {
    if (user.id == room.client.userID) continue;
    await room.client.kick(room.id, user.id, reason: reason);
  }
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
/// may delete it.
class GruppechatDeleteRoomTile extends StatelessWidget {
  final Room room;

  const GruppechatDeleteRoomTile({required this.room, super.key});

  @override
  Widget build(BuildContext context) {
    if (!gruppechatCanDeleteRoom(room)) return const SizedBox.shrink();
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
      future: () =>
          gruppechatDeleteRoom(room, reason: l10n.gruppechatChatWasDeleted),
    );
    if (result.error == null) router.go('/rooms');
  }
}
