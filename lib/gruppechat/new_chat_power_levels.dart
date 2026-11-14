// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call_member.dart';
import 'package:matrix/matrix.dart';

import 'group_state.dart';
import 'message_lifetime.dart';

/// Power levels for a chat made in the app, public or private. Every member
/// may change the general chat settings (`state_default` 0): name, picture,
/// topic, pinned messages. Access, security and roles stay with moderators
/// and admins.
///
/// Synapse replaces its whole default `events` map with this one, so every
/// state type that must not be open to everyone is listed here. New
/// sensitive state types have to be added.
Map<String, Object?> newChatPowerLevels() => withGroupPowerLevels({
  'state_default': 0,
  'events': <String, Object?>{
    EventTypes.RoomPowerLevels: 100,
    EventTypes.HistoryVisibility: 100,
    EventTypes.Encryption: 100,
    EventTypes.RoomTombstone: 100,
    'm.room.server_acl': 100,
    'm.room.retention': 100,
    'm.room.policy': 100,
    'org.matrix.msc4284.policy': 100,
    EventTypes.RoomJoinRules: 50,
    EventTypes.GuestAccess: 50,
    EventTypes.RoomCanonicalAlias: 50,
    'm.room.third_party_invite': 50,
    EventTypes.SpaceParent: 50,
    EventTypes.SpaceChild: 50,
    'im.vector.modular.widgets': 50,
    'm.widget': 50,
    // Disappearing messages delete everyone's messages
    gruppechatLifetimeType: 50,
    MatrixRtcCallMember.eventType: 0,
  },
});
