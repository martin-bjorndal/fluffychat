// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

/// Where a bot lists its commands in its membership of a room, as the
/// feedback bot does (bot/lib/src/commands.dart):
///
///     {"owner": "@martin:…", "commands": [
///       {"command": "!status", "description": "…", "owner_only": false}]}
const gruppechatBotCommandsKey = 'im.gruppechat.bot_commands';

class GruppechatBotCommand {
  final String command;
  final String description;

  const GruppechatBotCommand(this.command, this.description);
}

/// The commands of the bots in [room] that fit what has been typed so far,
/// [typed], when it is the start of a command: «!» and letters, at the very
/// start of the message. Commands only a bot's owner may use are left out
/// for everyone else.
List<GruppechatBotCommand> gruppechatBotCommandSuggestions(
  Room room,
  String typed,
) {
  final match = RegExp(r'^!(\w*)$').firstMatch(typed);
  if (match == null) return const [];
  final search = match[1]!.toLowerCase();
  final suggestions = <GruppechatBotCommand>[];
  final members = room.states[EventTypes.RoomMember]?.values;
  for (final member in members ?? const <StrippedStateEvent>[]) {
    if (member.content['membership'] != Membership.join.name) continue;
    final listed = member.content.tryGetMap<String, Object?>(
      gruppechatBotCommandsKey,
    );
    if (listed == null) continue;
    final isOwner = listed['owner'] == room.client.userID;
    final commands = listed['commands'];
    if (commands is! List) continue;
    for (final entry in commands.whereType<Map>()) {
      final command = entry['command'];
      final description = entry['description'];
      if (command is! String || !command.startsWith('!')) continue;
      if (entry['owner_only'] == true && !isOwner) continue;
      if (!command.substring(1).toLowerCase().startsWith(search)) continue;
      suggestions.add(
        GruppechatBotCommand(command, description is String ? description : ''),
      );
    }
  }
  return suggestions;
}

/// Makes sure the memberships of [room] are in memory, where
/// [gruppechatBotCommandSuggestions] looks for bots: the app only keeps
/// those of people who wrote lately, and of everyone once the list of
/// members has been opened. The chat page calls it when a chat opens.
Future<void> gruppechatPrepareBotCommands(Room room) async {
  try {
    await room.requestParticipants(const [Membership.join], true, true);
  } catch (e, s) {
    Logs().w('Could not load the members of ${room.id}', e, s);
  }
}
