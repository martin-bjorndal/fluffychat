// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

extension GruppechatMessageActionsExtension on Event {
  /// Whether double tapping this message edits it instead of reacting to it:
  /// the user's own text messages, once they are sent.
  bool get editsOnDoubleTap =>
      senderId == room.client.userID &&
      type == EventTypes.Message &&
      messageType == MessageTypes.Text &&
      status.isSent &&
      !redacted;
}
