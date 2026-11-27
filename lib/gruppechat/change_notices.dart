// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:collection/collection.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:matrix/matrix.dart';

import 'group_state.dart';
import 'matrix_group.dart';
import 'membership.dart';

/// A small line in a chat saying who changed its background, colour or a
/// nickname, like the lines Matrix shows when someone joins. The changes
/// themselves live in the group's space (see [GruppechatGroup]), which nobody
/// reads as a chat, so the app also posts this line in the chat the change
/// was made from, or for a nickname or picture set from the space's member
/// list, in its first channel.
///
/// It is sent unencrypted, also in encrypted chats: an encrypted event
/// matches the default push rule for encrypted messages and would wake
/// everyone's phone, while this type matches no rule. It tells the server
/// nothing new: nicknames are in the space's unencrypted state, and the
/// background itself isn't included.
const String gruppechatChangeType = 'im.gruppechat.change';

enum GroupChange {
  groupBackground('group_background'),
  chatBackground('chat_background'),
  chatColor('chat_color'),
  nickname('nickname'),
  avatar('avatar');

  final String key;
  const GroupChange(this.key);

  static GroupChange? fromKey(Object? key) =>
      values.where((change) => change.key == key).firstOrNull;
}

/// Posts a [GroupChange] line in [chat], the chat the change was made from.
/// Best effort: the change is already made, so a failure is only logged.
/// Nothing is posted in a space. The content holds no `body` and no names:
/// the default push rules match names in `body` whatever the event type.
Future<void> announceGroupChange(
  Room? chat,
  GroupChange change, {
  String? userId,
  String? nickname,
  bool removed = false,
}) async {
  if (chat == null || chat.isSpace || chat.membership != Membership.join) {
    return;
  }
  final name = nickname?.trim();
  final content = <String, Object?>{
    'kind': change.key,
    'user': ?userId,
    if (name != null && name.isNotEmpty) 'nickname': name,
    if (removed) 'removed': true,
  };
  try {
    await chat.client.sendMessage(
      chat.id,
      gruppechatChangeType,
      chat.client.generateUniqueTransactionId(),
      content,
    );
  } catch (e, s) {
    Logs().w('Could not post the change line in ${chat.id}', e, s);
  }
}

/// Which background change setting [group]'s background, or with [channel]
/// that channel's own, is: a direct chat's or a standalone group chat's
/// background is the chat's own.
GroupChange backgroundChangeFor(GruppechatGroup group, Room? channel) =>
    channel == null && group.space.isSpace
    ? GroupChange.groupBackground
    : GroupChange.chatBackground;

/// The chat a nickname or picture change made from [from]'s member list is
/// told in: [from] itself, or when that is [group]'s space, which nobody
/// reads as a chat, the first of its channels this user may post the line
/// in, in the order of [gruppechatChannelsInOrder], so it is the same channel
/// every time.
Room? changeLineChatFor(GruppechatGroup group, Room? from) {
  if (from == null || !from.isSpace || from.id != group.space.id) return from;
  return gruppechatChannelsInOrder(from).firstWhereOrNull(
    (room) => !room.isSpace && room.canSendEvent(gruppechatChangeType),
  );
}

/// Sets [userId]'s group nickname, as the nickname dialog does, and says so
/// in the chat whose member list it was set from (see [changeLineChatFor]).
/// Saving the name it already has changes nothing and says nothing.
Future<void> changeGroupNickname(
  GruppechatGroup group,
  String userId,
  String name, {
  Room? from,
}) async {
  if ((group.state.nicknameOf(userId)?.name ?? '') == name.trim()) return;
  await group.setNickname(userId, name);
  await announceGroupChange(
    changeLineChatFor(group, from),
    GroupChange.nickname,
    userId: userId,
    nickname: name,
  );
}

/// Whether the current user may give [userId] a picture in [group]: anyone
/// who may set pictures, unless [userId] has locked their nickname and
/// picture, which only they can then change.
bool mayChangeGroupAvatar(GruppechatGroup group, String userId) =>
    group.canSetMemberAvatars &&
    (group.space.client.userID == userId ||
        !group.state.isNicknameLocked(userId));

/// Gives [userId] the picture [url] in [group], or with null removes the
/// one they have there, as the member menu does, and says so in the chat
/// whose member list it was set from (see [changeLineChatFor]). The line
/// holds no picture, only that it changed. Picking the picture they
/// have, removing one they don't have, or changing a locked one does
/// nothing. Returns whether it changed.
Future<bool> changeGroupAvatar(
  GruppechatGroup group,
  String userId,
  Uri? url, {
  Room? from,
}) async {
  if (!mayChangeGroupAvatar(group, userId)) return false;
  if (group.state.avatarOf(userId) == url) return false;
  await group.setMemberAvatar(userId, url);
  await announceGroupChange(
    changeLineChatFor(group, from),
    GroupChange.avatar,
    userId: userId,
    removed: url == null,
  );
  return true;
}

/// [group]'s background, or with [channel] that channel's own.
GroupBackground? groupBackgroundOf(GruppechatGroup group, Room? channel) =>
    channel == null
    ? group.state.background
    : channel.gruppechatChannelBackground;

/// Sets [group]'s background, or with [channel] that channel's own, as the
/// background menu does, and says so in [channel] or else [from], the chat
/// the menu was opened from. Picking the one it has changes nothing.
Future<void> changeGroupBackground(
  GruppechatGroup group,
  GroupBackground? background, {
  Room? channel,
  Room? from,
}) async {
  if (const DeepCollectionEquality().equals(
    groupBackgroundOf(group, channel)?.toContent(),
    background?.toContent(),
  )) {
    return;
  }
  await (channel == null
      ? group.setBackground(background)
      : group.setChannelBackground(channel, background));
  await announceGroupChange(
    channel ?? from,
    backgroundChangeFor(group, channel),
  );
}

/// Sets [chat]'s colour, as the colour dialog does, and says so there.
Future<void> changeChatColor(
  GruppechatGroup group,
  Room chat,
  int? color,
) async {
  if (chat.gruppechatChatColor == color) return;
  await group.setChatColor(chat, color);
  await announceGroupChange(chat, GroupChange.chatColor);
}

/// Longest group nickname: what the nickname dialog allows, and what a
/// change line shows.
const int gruppechatMaxNicknameLength = 64;

/// The change [event] tells of, and whose nickname for a nickname change,
/// or null when it isn't a change line this version can show.
(GroupChange, String?)? _parse(Event event) {
  if (event.type != gruppechatChangeType || event.redacted) return null;
  final change = GroupChange.fromKey(event.content['kind']);
  if (change == null) return null;
  final user = event.content.tryGet<String>('user');
  if ((change == GroupChange.nickname || change == GroupChange.avatar) &&
      user == null) {
    return null;
  }
  return (change, user);
}

/// What an `m.room.pinned_events` event did, for the line saying so.
enum PinChange { pinned, unpinned }

/// Whether [event] pinned or unpinned a message, comparing its list with
/// the one before (`prev_content`, which the server leaves out only when
/// nothing was pinned yet). Null for any other event, or one that changed
/// nothing. A list that both gains and loses a message counts as pinned.
PinChange? pinChangeOf(Event event) {
  if (event.type != EventTypes.RoomPinnedEvents || event.redacted) {
    return null;
  }
  Set<Object?> idsIn(Map<String, Object?>? content) =>
      switch (content?['pinned']) {
        final List<Object?> ids => ids.toSet(),
        _ => const {},
      };
  final now = idsIn(event.content);
  final before = idsIn(event.prevContent);
  if (now.difference(before).isNotEmpty) return PinChange.pinned;
  if (before.difference(now).isNotEmpty) return PinChange.unpinned;
  return null;
}

/// Whether [event] is a line saying who changed what that this version can
/// show: a [gruppechatChangeType] line, or a message pinned or unpinned.
bool isGroupChangeLine(Event event) =>
    _parse(event) != null || pinChangeOf(event) != null;

/// The line a [gruppechatChangeType] event or a pin shows, or null for any
/// other event or one this version doesn't understand.
String? groupChangeText(Event event, L10n l10n) {
  final pin = pinChangeOf(event);
  if (pin != null) {
    final name = event.senderFromMemoryOrFallback.calcDisplayname();
    return switch (pin) {
      PinChange.pinned => l10n.gruppechatPinnedMessage(name),
      PinChange.unpinned => l10n.gruppechatUnpinnedMessage(name),
    };
  }
  final parsed = _parse(event);
  if (parsed == null) return null;
  final (change, userId) = parsed;
  // Their own names, not the group nicknames, which change later
  final name = event.senderFromMemoryOrFallback.calcDisplayname();
  switch (change) {
    case GroupChange.groupBackground:
      return l10n.gruppechatChangedGroupBackground(name);
    case GroupChange.chatBackground:
      return l10n.gruppechatChangedChatBackground(name);
    case GroupChange.chatColor:
      return l10n.gruppechatChangedChatColor(name);
    case GroupChange.nickname:
      var nickname = event.content.tryGet<String>('nickname');
      if (nickname != null &&
          nickname.characters.length > gruppechatMaxNicknameLength) {
        nickname = '${nickname.characters.take(gruppechatMaxNicknameLength)}…';
      }
      if (userId == event.senderId) {
        return nickname == null
            ? l10n.gruppechatDroppedNickname(name)
            : l10n.gruppechatTookNickname(name, nickname);
      }
      final user = event.room
          .unsafeGetUserFromMemoryOrFallback(userId!)
          .calcDisplayname();
      return nickname == null
          ? l10n.gruppechatRemovedNickname(name, user)
          : l10n.gruppechatGaveNickname(name, user, nickname);
    case GroupChange.avatar:
      final removed = event.content['removed'] == true;
      if (userId == event.senderId) {
        return removed
            ? l10n.gruppechatDroppedGroupPicture(name)
            : l10n.gruppechatTookGroupPicture(name);
      }
      final user = event.room
          .unsafeGetUserFromMemoryOrFallback(userId!)
          .calcDisplayname();
      return removed
          ? l10n.gruppechatRemovedGroupPicture(name, user)
          : l10n.gruppechatGaveGroupPicture(name, user);
  }
}
