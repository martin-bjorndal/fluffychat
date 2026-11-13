// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:collection/collection.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:matrix/matrix.dart';

import 'group_state.dart';
import 'matrix_group.dart';

/// A small line in a chat saying who changed its background, colour or a
/// nickname, like the lines Matrix shows when someone joins. The changes
/// themselves live in the group's space (see [GruppechatGroup]), which nobody
/// reads as a chat, so the app also posts this line in the chat the change
/// was made from.
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
  nickname('nickname');

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
}) async {
  if (chat == null || chat.isSpace || chat.membership != Membership.join) {
    return;
  }
  final name = nickname?.trim();
  final content = <String, Object?>{
    'kind': change.key,
    'user': ?userId,
    if (name != null && name.isNotEmpty) 'nickname': name,
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

/// Sets [userId]'s group nickname, as the nickname dialog does, and says so
/// in [from], the chat whose member list it was set from. Saving the name
/// it already has changes nothing and says nothing.
Future<void> changeGroupNickname(
  GruppechatGroup group,
  String userId,
  String name, {
  Room? from,
}) async {
  if ((group.state.nicknameOf(userId)?.name ?? '') == name.trim()) return;
  await group.setNickname(userId, name);
  await announceGroupChange(
    from,
    GroupChange.nickname,
    userId: userId,
    nickname: name,
  );
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
  if (change == GroupChange.nickname && user == null) return null;
  return (change, user);
}

/// Whether [event] is a change line this version can show.
bool isGroupChangeLine(Event event) => _parse(event) != null;

/// The line a [gruppechatChangeType] event shows, or null for any other
/// event or one this version doesn't understand.
String? groupChangeText(Event event, L10n l10n) {
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
  }
}
