// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

/// Where a bot lists its commands in its membership of a room, as the
/// feedback bot does (bot/lib/src/commands.dart):
///
///     {"owner": "@martin:…", "commands": [
///       {"command": "!status", "description": "…", "owner_only": false}]}
///
/// A command may list what can follow it, as the chat bot's «!modell» does
/// with its models and their prices, and say that a bot's name may follow
/// that, for the command to go to that bot only:
///
///       {"command": "!modell", …, "bot_argument": true,
///        "arguments": [{"value": "opus-5-5", "description": "…"}]}
const gruppechatBotCommandsKey = 'im.gruppechat.bot_commands';

class GruppechatBotCommand {
  /// What the message becomes when it is picked: the command, or the
  /// command with what follows it.
  final String command;
  final String description;

  const GruppechatBotCommand(this.command, this.description);
}

/// What the bots in [room] list: each bot's display name and its commands
/// that [room]'s user may use (owners' commands only for the owner).
List<({String bot, List<Map> commands})> _listedCommands(Room room) {
  final listings = <({String bot, List<Map> commands})>[];
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
    final name = member.content['displayname'];
    listings.add((
      bot: name is String && name.isNotEmpty
          ? name
          : (member.stateKey ?? '').localpart ?? '',
      commands: [
        for (final entry in commands.whereType<Map>())
          if (entry['command'] is String &&
              (entry['command'] as String).startsWith('!') &&
              !(entry['owner_only'] == true && !isOwner))
            entry,
      ],
    ));
  }
  return listings;
}

/// The commands of the bots in [room] that fit what has been typed so far,
/// [typed], at the very start of the message: after «!» and letters, the
/// commands; after a command and a space, what may follow it, such as a
/// model and its price; and after that, when there are several bots in the
/// chat with the command, their names. Commands only a bot's owner may use
/// are left out for everyone else.
List<GruppechatBotCommand> gruppechatBotCommandSuggestions(
  Room room,
  String typed,
) {
  final listings = _listedCommands(room);
  final suggestions = <GruppechatBotCommand>[];
  final seen = <String>{};
  void add(String command, Object? description) {
    if (!seen.add(command)) return;
    suggestions.add(
      GruppechatBotCommand(command, description is String ? description : ''),
    );
  }

  final commandOnly = RegExp(r'^!(\w*)$').firstMatch(typed);
  if (commandOnly != null) {
    final search = commandOnly[1]!.toLowerCase();
    for (final listing in listings) {
      for (final entry in listing.commands) {
        final command = entry['command'] as String;
        if (command.substring(1).toLowerCase().startsWith(search)) {
          add(command, entry['description']);
        }
      }
    }
    return suggestions;
  }

  final withArgument = RegExp(r'^(!\w+) (\S*)$').firstMatch(typed);
  if (withArgument != null) {
    final command = withArgument[1]!.toLowerCase();
    final search = withArgument[2]!.toLowerCase();
    for (final listing in listings) {
      for (final entry in listing.commands) {
        if ((entry['command'] as String).toLowerCase() != command) continue;
        final arguments = entry['arguments'];
        if (arguments is! List) continue;
        for (final argument in arguments.whereType<Map>()) {
          final value = argument['value'];
          if (value is! String || !value.toLowerCase().startsWith(search)) {
            continue;
          }
          add('${withArgument[1]} $value', argument['description']);
        }
      }
    }
    return suggestions;
  }

  final withBot = RegExp(r'^(!\w+) (\S+) (\S*)$').firstMatch(typed);
  if (withBot != null) {
    final command = withBot[1]!.toLowerCase();
    final search = withBot[3]!.toLowerCase();
    final bots = [
      for (final listing in listings)
        if (listing.commands.any(
          (entry) =>
              (entry['command'] as String).toLowerCase() == command &&
              entry['bot_argument'] == true,
        ))
          listing.bot,
    ];
    // Only worth picking one when there are several
    if (bots.length < 2) return suggestions;
    for (final bot in bots) {
      final word = bot.split(RegExp(r'\s+')).first;
      if (!word.toLowerCase().startsWith(search)) continue;
      add('${withBot[1]} ${withBot[2]} $word', 'Berre til $bot');
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
