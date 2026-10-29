// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pages/chat/chat.dart';
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
  Widget build(BuildContext context) =>
      _ReadPositionsScope(positions: _positions, child: widget.child);
}

class _ReadPositionsScope extends InheritedWidget {
  final Map<String, List<String>> positions;

  const _ReadPositionsScope({required this.positions, required super.child});

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
    final readerIds = context
        .dependOnInheritedWidgetOfExactType<_ReadPositionsScope>()
        ?.positions[event.eventId];
    if (readerIds == null || readerIds.isEmpty) {
      return const SizedBox.shrink();
    }
    final room = event.room;
    final readers = readerIds
        .take(_maxAvatars)
        .map(room.unsafeGetUserFromMemoryOrFallback);
    final ownMessage = event.senderId == room.client.userID;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: FluffyThemes.maxTimelineWidth,
        ),
        child: Align(
          alignment: ownMessage ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 1, 8, 4),
            child: Wrap(
              spacing: 4,
              children: [
                for (final reader in readers)
                  Tooltip(
                    message: reader.groupDisplayname(),
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
