// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'matrix_group.dart';
import 'threads.dart';

/// How many pages of older messages to load, at most, to reach the start of
/// an old thread before jumping to it instead.
const int _maxHistoryRequests = 30;
const int _historyPageSize = 100;

/// Lists every thread in the chat, most recently active first, and opens the
/// one the user picks.
Future<void> showGruppechatThreadList({
  required BuildContext context,
  required ChatController controller,
}) async {
  final rootId = await showAdaptiveBottomSheet<String>(
    context: context,
    builder: (context) => GruppechatThreadList(room: controller.room),
  );
  if (rootId == null || !context.mounted) return;
  await showFutureLoadingDialog(
    context: context,
    future: () => openGruppechatThread(controller, rootId),
  );
}

/// Opens the thread that starts with [rootId]. The thread view only shows
/// messages the chat has loaded, so for a thread that started further back,
/// older messages are loaded first. If it is too far back, the chat jumps to
/// the thread's first message instead.
Future<void> openGruppechatThread(
  ChatController controller,
  String rootId,
) async {
  final timeline = controller.timeline;
  if (timeline == null) return;
  bool isLoaded() => timeline.events.any((event) => event.eventId == rootId);
  for (var i = 0; i < _maxHistoryRequests && !isLoaded(); i++) {
    if (!timeline.canRequestHistory) break;
    final loadedBefore = timeline.events.length;
    await timeline.requestHistory(historyCount: _historyPageSize);
    if (timeline.events.length == loadedBefore) break;
  }
  if (!controller.mounted) return;
  controller.enterThread(rootId);
  if (!isLoaded()) await controller.scrollToEventId(rootId);
}

/// The list of a chat's threads, with a filter for the user's own threads.
/// Pops with the ID of the thread's first message when one is tapped.
class GruppechatThreadList extends StatefulWidget {
  final Room room;

  const GruppechatThreadList({required this.room, super.key});

  @override
  State<GruppechatThreadList> createState() => _GruppechatThreadListState();
}

class _GruppechatThreadListState extends State<GruppechatThreadList> {
  final List<GruppechatThread> _threads = [];
  String? _nextBatch;
  bool _onlyMine = false;
  bool _loading = true;
  Object? _error;

  /// Answers to requests made before the filter changed are dropped.
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final request = ++_request;
    try {
      final page = await widget.room.loadGruppechatThreads(
        onlyMine: _onlyMine,
        from: _nextBatch,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _threads.addAll(page.threads);
        _nextBatch = page.nextBatch;
        _error = null;
        _loading = false;
      });
    } on Object catch (e, s) {
      Logs().w('Unable to load the threads of ${widget.room.id}', e, s);
      if (!mounted || request != _request) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// Loads the next page, or tries the failed one again.
  Future<void> _loadMore() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    await _fetch();
  }

  Future<void> _setOnlyMine(bool onlyMine) async {
    if (onlyMine == _onlyMine) return;
    setState(() {
      _onlyMine = onlyMine;
      _threads.clear();
      _nextBatch = null;
      _error = null;
      _loading = true;
    });
    await _fetch();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final error = _error;
    return Scaffold(
      appBar: AppBar(
        leading: CloseButton(onPressed: Navigator.of(context).pop),
        title: Text(l10n.gruppechatThreads),
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: Text(l10n.all),
                  selected: !_onlyMine,
                  onSelected: (_) => _setOnlyMine(false),
                ),
                ChoiceChip(
                  label: Text(l10n.gruppechatMine),
                  selected: _onlyMine,
                  onSelected: (_) => _setOnlyMine(true),
                ),
              ],
            ),
          ),
          for (final thread in _threads)
            _ThreadTile(
              thread: thread,
              onTap: () => Navigator.of(context).pop(thread.root.eventId),
            ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator.adaptive()),
            )
          else if (error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(error.toLocalizedString(context)),
                  TextButton(onPressed: _loadMore, child: Text(l10n.tryAgain)),
                ],
              ),
            )
          else if (_threads.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                _onlyMine
                    ? l10n.gruppechatNoOwnThreads
                    : l10n.gruppechatNoThreads(l10n.replyInThread),
                textAlign: TextAlign.center,
              ),
            )
          else if (_nextBatch != null)
            Center(
              child: TextButton(
                onPressed: _loadMore,
                child: Text(l10n.loadMore),
              ),
            ),
        ],
      ),
    );
  }
}

class _ThreadTile extends StatelessWidget {
  final GruppechatThread thread;
  final VoidCallback onTap;

  const _ThreadTile({required this.thread, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final i18n = MatrixLocals(l10n);
    final root = thread.root;
    final senderName = _senderName(root, i18n);
    final replies = l10n.countReplies(thread.summary.replyCount);
    final latestReply = thread.latestReply;
    final latest = latestReply == null
        ? replies
        : '$replies · ${_senderName(latestReply, i18n)}: '
              '${_preview(latestReply, i18n)}';
    return ListTile(
      onTap: onTap,
      leading: Avatar(
        mxContent: root.senderFromMemoryOrFallback.avatarUrl,
        name: senderName,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              senderName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            thread.lastActivity.localizedTimeShort(context),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _preview(root, i18n),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            latest,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: theme.colorScheme.primary),
          ),
        ],
      ),
    );
  }
}

String _senderName(Event event, MatrixLocalizations i18n) =>
    event.senderFromMemoryOrFallback.groupDisplayname(i18n: i18n);

String _preview(Event event, MatrixLocalizations i18n) =>
    event.calcLocalizedBodyFallback(
      i18n,
      hideReply: true,
      plaintextBody: true,
      removeMarkdown: true,
    );
