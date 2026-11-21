// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:collection/collection.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/gruppechat/photo_stacks.dart';
import 'package:fluffychat/gruppechat/polls.dart';
import 'package:fluffychat/gruppechat/read_positions_widgets.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/encryption_info.dart';
import 'package:fluffychat/pages/chat/events/message.dart';
import 'package:fluffychat/pages/chat/typing_indicators.dart';
import 'package:fluffychat/utils/account_config.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import '../../config/app_config.dart';
import '../../utils/date_time_extension.dart';

class ChatEventList extends StatelessWidget {
  final ChatController controller;

  const ChatEventList({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final timeline = controller.timeline;

    if (timeline == null) {
      return const Center(child: CupertinoActivityIndicator());
    }
    final theme = Theme.of(context);

    final colors = [theme.secondaryBubbleColor, theme.bubbleColor];

    final horizontalPadding = FluffyThemes.isColumnMode(context) ? 8.0 : 0.0;

    // Gruppechat: no new messages at the bottom while reading further up,
    // and a poll shows where its newest vote is (lib/gruppechat/polls.dart)
    final movedPolls = <String, Event>{};
    var events = controller.shownEvents(moved: movedPolls);
    final readMarkerEventId = readMarkerShownAt(
      events,
      timeline,
      movedPolls,
      controller.readMarkerEventId,
    );
    // Gruppechat: photos sent together show as one stack
    final photoStacks = <String, List<Event>>{};
    events = stackPhotoSeries(events, photoStacks, timeline: timeline);

    // create a map of eventId --> index to greatly improve performance of
    // ListView's findChildIndexCallback
    final thisEventsKeyMap = <String, int>{};
    for (var i = 0; i < events.length; i++) {
      // Keyed as the list items are, so own messages keep their place too
      thisEventsKeyMap[events[i].transactionId ?? events[i].eventId] = i;
    }

    final hasWallpaper =
        controller.room.client.applicationAccountConfig.wallpaperUrl != null;

    final list = SelectionArea(
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(AppSettings.fontSizeFactor.value),
        ),
        child: ListView.custom(
          padding: EdgeInsets.only(
            top: 8 + MediaQuery.paddingOf(context).top,
            bottom:
                8 +
                (controller.inputBarHeight ??
                    (72 + (FluffyThemes.isColumnMode(context) ? 16 : 0))),
            left: horizontalPadding,
            right: horizontalPadding,
          ),
          reverse: true,
          controller: controller.scrollController,
          keyboardDismissBehavior: PlatformInfos.isIOS
              ? ScrollViewKeyboardDismissBehavior.onDrag
              : ScrollViewKeyboardDismissBehavior.manual,
          childrenDelegate: SliverChildBuilderDelegate(
            (BuildContext context, int i) {
              // Footer to display typing indicator and read receipts:
              if (i == 0) {
                if (timeline.canRequestFuture) {
                  return Center(
                    child: TextButton.icon(
                      onPressed: timeline.isRequestingFuture
                          ? null
                          : controller.requestFuture,
                      icon: timeline.isRequestingFuture
                          ? CircularProgressIndicator.adaptive(strokeWidth: 2)
                          : const Icon(Icons.arrow_downward_outlined),
                      label: Text(L10n.of(context).loadMore),
                    ),
                  );
                }
                return Column(
                  mainAxisSize: .min,
                  children: [
                    // Gruppechat: read receipts are shown under every
                    // message by GruppechatReadByRow instead of SeenByRow.
                    TypingIndicators(controller),
                    EncryptionInfo(room: controller.room),
                  ],
                );
              }

              // Request history button or progress indicator:
              if (i == events.length + 1) {
                if (controller.activeThreadId != null ||
                    !timeline.canRequestHistory) {
                  return const SizedBox.shrink();
                }
                return Builder(
                  builder: (context) {
                    final visibleIndex = timeline.events.lastIndexWhere(
                      (event) =>
                          !event.isCollapsedState && event.isVisibleInGui,
                    );
                    if (visibleIndex > timeline.events.length - 50) {
                      WidgetsBinding.instance.addPostFrameCallback(
                        controller.requestHistory,
                      );
                    }
                    return Center(
                      child: TextButton.icon(
                        onPressed: timeline.isRequestingHistory
                            ? null
                            : controller.requestHistory,
                        icon: timeline.isRequestingHistory
                            ? CircularProgressIndicator.adaptive(strokeWidth: 2)
                            : const Icon(Icons.arrow_upward_outlined),
                        label: Text(L10n.of(context).loadMore),
                      ),
                    );
                  },
                );
              }
              i--;

              // The message at this index:
              final event = events[i];
              final animateIn =
                  (event.transactionId ?? event.eventId) ==
                  controller.animateInEventId;

              final nextEvent = i + 1 < events.length ? events[i + 1] : null;
              final previousEvent = i > 0 ? events[i - 1] : null;

              // Collapsed state event
              final canExpand =
                  event.isCollapsedState &&
                  nextEvent?.isCollapsedState == true &&
                  previousEvent?.isCollapsedState != true;
              final isCollapsed =
                  event.isCollapsedState &&
                  previousEvent?.isCollapsedState == true &&
                  !controller.expandedEventIds.contains(event.eventId);

              // Gruppechat: the photos of a stack count as the stack
              final stack = GruppechatPhotoStacks.photosOf(photoStacks, event);
              bool isHere(String? eventId) =>
                  isInItem(photoStacks, event, eventId);

              final displayDate =
                  event.type == EventTypes.RoomCreate ||
                  nextEvent == null ||
                  !shownTime(
                    event,
                    movedPolls,
                  ).sameDay(shownTime(nextEvent, movedPolls));

              return AutoScrollTag(
                key: ValueKey(event.transactionId ?? event.eventId),
                index: i,
                controller: controller.scrollController,
                child: Column(
                  mainAxisSize: .min,
                  children: [
                    if (!isCollapsed && displayDate)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0, bottom: 16.0),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Material(
                              borderRadius: BorderRadius.circular(
                                AppConfig.borderRadius * 2,
                              ),
                              color: theme.colorScheme.inverseSurface.withAlpha(
                                200,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8.0,
                                  vertical: 2.0,
                                ),
                                child: Text(
                                  shownTime(
                                    event,
                                    movedPolls,
                                  ).localizedDate(context),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onInverseSurface,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    Message(
                      event,
                      bigEmojis: controller.bigEmojis,
                      animateIn: animateIn,
                      onSwipe: () => controller.replyAction(replyTo: event),
                      onInfoTab: controller.showEventInfo,
                      onMention: () => controller.sendController.text +=
                          '${event.senderFromMemoryOrFallback.mention} ',
                      highlightMarker: isHere(controller.scrollToEventIdMarker),
                      onSelect: controller.onSelectMessage,
                      scrollToEventId: controller.scrollToEventId,
                      longPressSelect: controller.selectedEvents.isNotEmpty,
                      selected: controller.selectedEvents.any(
                        (e) => e.eventId == event.eventId,
                      ),
                      singleSelected:
                          controller.selectedEvents.singleOrNull?.eventId ==
                          event.eventId,
                      // Gruppechat: edits this message (on double tap)
                      onEdit: () => controller.editEventAction(event),
                      timeline: timeline,
                      displayReadMarker: i > 0 && isHere(readMarkerEventId),
                      nextEvent: nextEvent,
                      previousEvent: previousEvent,
                      wallpaperMode: hasWallpaper,
                      scrollController: controller.scrollController,
                      colors: colors,
                      isCollapsed: isCollapsed,
                      enterThread: controller.activeThreadId == null
                          ? controller.enterThread
                          : null,
                      onExpand: canExpand
                          ? () => controller.expandEventsFrom(
                              event,
                              !controller.expandedEventIds.contains(
                                event.eventId,
                              ),
                            )
                          : null,
                    ),
                    // Gruppechat: who has read any photo of a stack
                    for (final shown in stack.isEmpty ? [event] : stack)
                      GruppechatReadByRow(event: shown),
                  ],
                ),
              );
            },
            childCount: events.length + 2,
            findChildIndexCallback: (key) =>
                controller.findChildIndexCallback(key, thisEventsKeyMap),
          ),
        ),
      ),
    );
    return GruppechatPhotoStacks(stacks: photoStacks, child: list);
  }
}
