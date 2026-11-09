// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';
import 'package:swipe_to_action/swipe_to_action.dart';

/// A quick reaction, as on a double tap: reacts to [event] with [emoji], or
/// takes the reaction back when the user has already reacted with it. A
/// reaction still on its way is left alone, as it can't be taken back yet.
Future<void> gruppechatQuickReact(
  Event event,
  Timeline timeline,
  String emoji,
) async {
  final ownReaction = event
      .aggregatedEvents(timeline, RelationshipTypes.reaction)
      .firstWhereOrNull(
        (e) =>
            e.senderId == event.room.client.userID &&
            e.content
                    .tryGetMap<String, Object?>('m.relates_to')
                    ?.tryGet<String>('key') ==
                emoji,
      );
  try {
    if (ownReaction == null) {
      await event.room.sendReaction(event.eventId, emoji);
    } else if (ownReaction.status.isSent) {
      await ownReaction.redactEvent();
    }
  } catch (e, s) {
    Logs().w('Could not react with $emoji', e, s);
  }
}

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
