// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// What an edited message said before: tapping "(redigert)" under it lists
// the original and every edit, oldest first.

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'captions.dart';

/// One version of an edited message: what it said from [time] on.
class MessageVersion {
  final DateTime time;
  final String text;
  const MessageVersion(this.time, this.text);

  @override
  bool operator ==(Object other) =>
      other is MessageVersion && other.time == time && other.text == text;

  @override
  int get hashCode => Object.hash(time, text);

  @override
  String toString() => 'MessageVersion($time, $text)';
}

/// The edits of [event] in [timeline] that change what it shows, as the
/// SDK's [Event.getDisplayEvent] picks them: made by its sender, as
/// messages, so the newest one is what the chat shows. Deleted edits don't
/// count.
Iterable<Event> _edits(Event event, Timeline timeline) => event
    .aggregatedEvents(timeline, RelationshipTypes.edit)
    .where(
      (e) =>
          e.senderId == event.senderId &&
          e.type == EventTypes.Message &&
          !e.redacted,
    );

/// Whether [event] shows "(redigert)": its sender has changed it, and it
/// isn't deleted. Edits by others change nothing, so they don't count.
bool gruppechatWasEdited(Event event, Timeline timeline) =>
    // Most messages have no edits, so that is checked first
    event.hasAggregatedEvents(timeline, RelationshipTypes.edit) &&
    !event.redacted &&
    _edits(event, timeline).isNotEmpty;

/// Every version of [event] in [timeline]: the original first, then each
/// edit (see [_edits]), oldest first. The text of a picture, video, sound
/// or file is its caption, as when editing it. Empty when it wasn't edited
/// (see [gruppechatWasEdited]); a deleted message has no versions, so what
/// it said stays gone. Edits this device hasn't loaded or can't decrypt
/// are missing, as they are from the chat.
List<MessageVersion> gruppechatEditHistory(
  Event event,
  Timeline timeline,
  MatrixLocalizations i18n,
) {
  if (event.redacted) return const [];
  final edits = _edits(event, timeline).toList();
  if (edits.isEmpty) return const [];
  // As getDisplayEvent sorts them, so the last is the one the chat shows
  edits.sort((a, b) => a.originServerTs.compareTo(b.originServerTs));
  return [
    MessageVersion(event.originServerTs, event.textToEdit(i18n)),
    for (final edit in edits)
      MessageVersion(
        edit.originServerTs,
        switch (edit.content['m.new_content']) {
          final Map newContent => Event.fromJson({
            ...edit.toJson(),
            'content': Map<String, Object?>.from(newContent),
          }, edit.room),
          // As the SDK shows an edit without new content
          _ => edit,
        }.textToEdit(i18n),
      ),
  ];
}

/// Shows the versions of [event] (see [gruppechatEditHistory]) in a dialog.
Future<void> showGruppechatEditHistory(
  BuildContext context,
  Event event,
  Timeline timeline,
) {
  final versions = gruppechatEditHistory(
    event,
    timeline,
    MatrixLocals(L10n.of(context)),
  );
  // Deleted since the label was drawn
  if (versions.isEmpty) return Future.value();
  return showDialog<void>(
    context: context,
    builder: (context) => GruppechatEditHistoryDialog(versions: versions),
  );
}

/// The versions of an edited message, oldest first.
class GruppechatEditHistoryDialog extends StatelessWidget {
  final List<MessageVersion> versions;
  const GruppechatEditHistoryDialog({required this.versions, super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final languageCode = Localizations.localeOf(context).languageCode;
    final thisYear = DateTime.now().year;
    String when(DateTime time) => l10n.dateAndTimeOfDay(
      (time.year == thisYear ? DateFormat.MMMd : DateFormat.yMMMd)(
        languageCode,
      ).format(time),
      time.localizedTimeOfDay(context),
    );
    return AlertDialog(
      title: Text(l10n.gruppechatEarlierVersions),
      content: SizedBox(
        width: 400,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: versions.length,
          separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (context, i) {
            final version = versions[i];
            final label = i == 0
                ? l10n.gruppechatOriginalVersion
                : i == versions.length - 1
                ? l10n.gruppechatCurrentVersion
                : null;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [?label, when(version.time)].join(' · '),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(version.text),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}

/// "(redigert)" under a message: tapping it shows what the message said
/// before, unless [enabled] is off (while messages are being selected).
class GruppechatEditedLabel extends StatelessWidget {
  final Event event;
  final Timeline timeline;
  final bool enabled;
  final Widget child;
  const GruppechatEditedLabel({
    required this.event,
    required this.timeline,
    required this.enabled,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    // The same padding either way, so the label stays put while selecting;
    // it also keeps it apart from the time before it
    final label = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: child,
    );
    if (!enabled) return label;
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => showGruppechatEditHistory(context, event, timeline),
        child: label,
      ),
    );
  }
}
