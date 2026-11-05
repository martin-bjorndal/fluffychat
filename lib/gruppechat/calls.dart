// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

extension GruppechatCallAnnouncement on Room {
  /// Tells the others that a call has started: it rings the other person in
  /// a direct chat, and notifies the members of a group chat.
  Future<String?> announceCall() {
    final dmUserId = directChatMatrixID;
    if (dmUserId != null) {
      return sendRtcNotification(type: .ring, userIds: [dmUserId]);
    }
    return sendRtcNotification(type: .notification, mentionRoom: true);
  }
}

extension GruppechatIncomingCall on Event {
  /// Whether this tells everyone in a chat that isn't muted that a call has
  /// started. It mentions the whole room, which only notifies when moderators
  /// send it, but anyone in a group may start a call.
  bool get announcesCallToAll =>
      type == RtcNotificationContent.eventType &&
      tryParseRtcNotificationContent()?.notificationType == .notification &&
      room.pushRuleState == PushRuleState.notify;

  /// Whether this pushed event rings the phone as an incoming call.
  bool get ringsAsCall =>
      type == RtcNotificationContent.eventType &&
      tryParseRtcNotificationContent()?.notificationType == .ring;
}
