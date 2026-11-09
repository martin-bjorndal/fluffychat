// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'matrix_group.dart';
import 'read_positions.dart';

const int _maxAvatars = 7;

/// Works out how far down the chat everyone has read, and keeps it up to
/// date as read receipts arrive. The [GruppechatReadByRow]s below it show
/// the result under the messages.
class GruppechatReadPositions extends StatefulWidget {
  final ChatController controller;
  final Widget child;

  const GruppechatReadPositions({
    required this.controller,
    required this.child,
    super.key,
  });

  @override
  State<GruppechatReadPositions> createState() =>
      _GruppechatReadPositionsState();
}

class _GruppechatReadPositionsState extends State<GruppechatReadPositions> {
  StreamSubscription<SyncUpdate>? _receiptUpdates;
  String? _listeningTo;
  Map<String, List<String>> _positions = const {};

  @override
  void initState() {
    super.initState();
    _listen();
    _positions = _compute();
  }

  @override
  void didUpdateWidget(GruppechatReadPositions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller.room.id != _listeningTo) _listen();
    _positions = _compute();
  }

  @override
  void dispose() {
    _receiptUpdates?.cancel();
    super.dispose();
  }

  /// Recomputes the read positions whenever new read receipts arrive.
  void _listen() {
    _receiptUpdates?.cancel();
    final room = widget.controller.room;
    _listeningTo = room.id;
    _receiptUpdates = room.client.onSync.stream
        .where(
          (update) =>
              update.rooms?.join?[room.id]?.ephemeral?.any(
                (event) => event.type == 'm.receipt',
              ) ??
              false,
        )
        .listen((_) {
          if (mounted) setState(() => _positions = _compute());
        });
  }

  Map<String, List<String>> _compute() {
    final controller = widget.controller;
    final timeline = controller.timeline;
    if (timeline == null) return const {};
    return gruppechatReadPositions(
      timeline: timeline,
      threadId: controller.activeThreadId,
      expandedEventIds: controller.expandedEventIds,
    );
  }

  @override
  Widget build(BuildContext context) => _ReadPositionsScope(
    positions: _positions,
    controller: widget.controller,
    child: widget.child,
  );
}

class _ReadPositionsScope extends InheritedWidget {
  final Map<String, List<String>> positions;
  final ChatController controller;

  const _ReadPositionsScope({
    required this.positions,
    required this.controller,
    required super.child,
  });

  @override
  bool updateShouldNotify(_ReadPositionsScope oldWidget) =>
      !const DeepCollectionEquality().equals(oldWidget.positions, positions);
}

/// Small avatars under [event] for everyone whose read position is there.
class GruppechatReadByRow extends StatelessWidget {
  final Event event;

  const GruppechatReadByRow({required this.event, super.key});

  @override
  Widget build(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_ReadPositionsScope>();
    final readerIds = scope?.positions[event.eventId];
    if (readerIds == null || readerIds.isEmpty) {
      return const SizedBox.shrink();
    }
    final room = event.room;
    final readers = readerIds
        .take(_maxAvatars)
        .map(room.unsafeGetUserFromMemoryOrFallback);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: FluffyThemes.maxTimelineWidth,
        ),
        child: Align(
          alignment: Alignment.centerRight,
          // Tapping the faces lists everyone who has read the message
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => showGruppechatReaders(
              context: context,
              controller: scope!.controller,
              event: event,
              positions: scope.positions,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
              child: Wrap(
                spacing: 4,
                children: [
                  for (final reader in readers)
                    Tooltip(
                      message: reader.groupDisplayname(),
                      // The same avatar as next to their messages: letter
                      // and colour from the group nickname
                      child: Avatar(
                        mxContent: reader.avatarUrl,
                        name: reader.groupDisplayname(),
                        size: 16,
                      ),
                    ),
                  if (readerIds.length > _maxAvatars)
                    _MoreReaders(count: readerIds.length - _maxAvatars),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MoreReaders extends StatelessWidget {
  final int count;

  const _MoreReaders({required this.count});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 16,
    height: 16,
    child: Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(32),
      child: Center(
        child: Text('+$count', style: const TextStyle(fontSize: 9)),
      ),
    ),
  );
}

/// Lists everyone who has read [event] by their full names, as Messenger
/// does: from the selected message's menu or by tapping the faces under a
/// message. Worked out the same way as those faces.
Future<void> showGruppechatReaders({
  required BuildContext context,
  required ChatController controller,
  required Event event,
  Map<String, List<String>>? positions,
}) {
  final timeline = controller.timeline;
  final room = event.room;
  final readerIds = timeline == null
      ? <String>[]
      // The faces already know the positions; the message menu works them out
      : positions != null
      ? readersOf(
          event.eventId,
          timeline: [for (final event in timeline.events) event.eventId],
          positions: positions,
          senderId: event.senderId,
        )
      : gruppechatReadersOf(
          timeline: timeline,
          event: event,
          threadId: controller.activeThreadId,
          expandedEventIds: controller.expandedEventIds,
        );
  final readers = [
    for (final user in readerIds.map(room.unsafeGetUserFromMemoryOrFallback))
      (user: user, name: user.groupDisplayname()),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return showAdaptiveBottomSheet<void>(
    context: context,
    builder: (context) {
      final l10n = L10n.of(context);
      final theme = Theme.of(context);
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(
                l10n.gruppechatReadBy,
                style: theme.textTheme.titleMedium,
              ),
              subtitle: Text(l10n.gruppechatReadersHint),
            ),
            if (readers.isEmpty)
              ListTile(title: Text(l10n.gruppechatNoReadersYet)),
            for (final (:user, :name) in readers)
              ListTile(
                leading: Avatar(mxContent: user.avatarUrl, name: name),
                title: Text(name),
              ),
          ],
        ),
      );
    },
  );
}
