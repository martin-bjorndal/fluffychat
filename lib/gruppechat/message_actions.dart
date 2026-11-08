// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';
import 'package:swipe_to_action/swipe_to_action.dart';

extension GruppechatMessageActionsExtension on Event {
  /// Whether double tapping this message edits it instead of reacting to it:
  /// the user's own text messages, once they are sent.
  bool get editsOnDoubleTap =>
      senderId == room.client.userID &&
      type == EventTypes.Message &&
      messageType == MessageTypes.Text &&
      status.isSent &&
      !redacted;

  /// Which way to swipe this message to reply to it. The user's own
  /// messages sit on the right, so they are swiped to the left, away from
  /// the edge; other people's follow the "swipe right to left" setting.
  SwipeDirection replySwipeDirection({required bool rightToLeftSetting}) =>
      rightToLeftSetting || senderId == room.client.userID
      ? SwipeDirection.endToStart
      : SwipeDirection.startToEnd;
}
