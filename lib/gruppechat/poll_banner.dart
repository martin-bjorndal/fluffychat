// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/gruppechat/polls.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/chat_app_bar_list_tile.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// The polls whose banner someone closed, by account and chat, while the
/// app runs.
final _closed = <String, Set<String>>{};

Set<String> _closedIn(Room room) =>
    _closed['${room.client.userID} ${room.id}'] ??= {};

/// The poll the banner at the top of the chat asks the person to answer
/// ([unansweredPoll]), or null. Not in a thread, and not while the banner
/// about new messages shows, so the bars above the chat don't pile up, and
/// not for someone who may not vote in the chat.
Event? pollBannerFor(ChatController controller) {
  final timeline = controller.timeline;
  final userId = controller.room.client.userID;
  if (timeline == null ||
      userId == null ||
      !controller.room.canSendEvent(PollEventContent.responseType) ||
      controller.activeThreadId != null ||
      controller.scrollUpBannerEventId != null) {
    return null;
  }
  return unansweredPoll(
    timeline,
    userId,
    dismissed: _closedIn(controller.room),
  );
}

/// A bar at the top of the chat for [poll], which the person hasn't
/// answered ([pollBannerFor]): tapping it goes to the poll, the cross hides
/// it and the other unanswered polls in the chat.
class UnansweredPollBanner extends StatelessWidget {
  final ChatController controller;
  final Event poll;

  const UnansweredPollBanner(this.controller, this.poll, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final question = poll.parsedPollEventContent.pollStartContent.question.mText
        .replaceAll('\n', ' ');
    return ChatAppBarListTile(
      leading: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Icon(
          Icons.poll_outlined,
          size: 18,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      title: L10n.of(context).gruppechatAnswerPoll(question),
      onTap: () => controller.scrollToEventId(poll.eventId),
      trailing: IconButton(
        color: theme.colorScheme.onSurfaceVariant,
        icon: const Icon(Icons.close),
        tooltip: L10n.of(context).close,
        onPressed: () {
          final timeline = controller.timeline;
          final userId = controller.room.client.userID;
          if (timeline == null || userId == null) return;
          dismissUnansweredPolls(timeline, userId, _closedIn(controller.room));
          controller.updateView();
        },
      ),
    );
  }
}
