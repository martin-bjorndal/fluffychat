// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Client-side channel mute. FluffyChat mutes a chat with a server push rule
// that stops every push from it. In an encrypted chat the server can't see
// mentions, so a muted channel could never wake the phone for @role or
// @user. For each muted group channel we therefore add a "wake" rule that
// still pushes encrypted messages; the app decrypts them and only notifies
// when the user or one of their roles is mentioned (see push_helper.dart).
// The muted state itself stays the room rule FluffyChat already uses, so
// every mute switch in the app keeps working unchanged.

import 'dart:async';

import 'package:matrix/matrix.dart';

import 'matrix_group.dart';

const String _wakeRulePrefix = 'im.gruppechat.wake.';

/// Push rule ID of the wake rule for the channel [roomId].
String wakeRuleId(String roomId) => '$_wakeRulePrefix$roomId';

/// The room a wake rule belongs to, or null for any other rule.
String? roomIdFromWakeRuleId(String ruleId) =>
    ruleId.startsWith(_wakeRulePrefix)
    ? ruleId.substring(_wakeRulePrefix.length)
    : null;

/// The wake rules to add and to remove so that exactly the channels in
/// [mutedChannelIds] have one. [existingRuleIds] are the IDs of the
/// account's override push rules.
({Set<String> add, Set<String> remove}) wakeRuleChanges({
  required Set<String> mutedChannelIds,
  required Iterable<String> existingRuleIds,
}) {
  final existing = existingRuleIds
      .map(roomIdFromWakeRuleId)
      .whereType<String>()
      .toSet();
  return (
    add: mutedChannelIds.difference(existing),
    remove: existing.difference(mutedChannelIds),
  );
}

extension GruppechatChannelMuteRoomExtension on Room {
  /// A joined, encrypted group chat or channel muted to mentions only.
  /// Fully silenced chats ([PushRuleState.dontNotify]) get no wake rule.
  bool get isMutedGroupChannel =>
      membership == Membership.join &&
      !isSpace &&
      encrypted &&
      pushRuleState == PushRuleState.mentionsOnly &&
      GruppechatGroup.of(this) != null;
}

extension GruppechatChannelMuteEventExtension on Event {
  /// Whether this event only reached the device through a wake rule and
  /// couldn't be decrypted, so there is nothing to check for mentions.
  bool get isUndecryptedWakeUp =>
      type == EventTypes.Encrypted &&
      room.pushRuleState == PushRuleState.mentionsOnly;
}

/// Keeps the account's wake rules in line with which channels are muted.
class GruppechatWakeRules {
  final Client client;
  StreamSubscription<SyncUpdate>? _subscription;
  bool _running = false;
  final Set<String> _failed = {};

  GruppechatWakeRules(this.client);

  void start() {
    _subscription ??= client.onSync.stream.listen((_) => update());
  }

  Future<void> cancel() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  /// Adds and removes wake rules. Rules that fail are left alone until the
  /// app restarts, so a server error can't cause a request on every sync.
  Future<void> update() async {
    final rules = client.globalPushRules;
    if (_running || rules == null || !client.isLogged()) return;
    _running = true;
    try {
      final changes = wakeRuleChanges(
        mutedChannelIds: {
          for (final room in client.rooms)
            if (room.isMutedGroupChannel) room.id,
        },
        existingRuleIds: [for (final rule in rules.override ?? []) rule.ruleId],
      );
      for (final roomId in changes.add.difference(_failed)) {
        try {
          await client.setPushRule(
            PushRuleKind.override,
            wakeRuleId(roomId),
            ['notify'],
            conditions: [
              PushCondition(
                kind: PushRuleConditions.eventMatch.name,
                key: 'room_id',
                pattern: roomId,
              ),
              PushCondition(
                kind: PushRuleConditions.eventMatch.name,
                key: 'type',
                pattern: EventTypes.Encrypted,
              ),
            ],
          );
        } catch (e, s) {
          _failed.add(roomId);
          Logs().w('Could not add the wake rule for $roomId', e, s);
        }
      }
      for (final roomId in changes.remove.difference(_failed)) {
        try {
          await client.deletePushRule(
            PushRuleKind.override,
            wakeRuleId(roomId),
          );
        } catch (e, s) {
          _failed.add(roomId);
          Logs().w('Could not remove the wake rule for $roomId', e, s);
        }
      }
    } finally {
      _running = false;
    }
  }
}
