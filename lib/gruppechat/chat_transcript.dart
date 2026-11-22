// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Downloading a whole chat as a Markdown file, from the chat's settings.
//
// The file holds what the chat shows, the way it shows it: the same events
// (`isVisibleInGui`, so what has disappeared, the lifetime setting and
// anything else the chat hides stays out), the latest version of edited
// messages, "Deleted by …" for deleted ones, the app's own names (group
// nicknames included) and its own words for pictures, files and lines such
// as someone joining. Pictures and files are named, not downloaded.
//
// The format: a heading with the chat's name, a line saying when it was
// downloaded and by whom, then a heading per day with the messages oldest
// first, each as "**Name** (14:05): text". A message of several lines
// follows its name as a block quote. Replies and thread messages say what
// they answer next to the time.

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:fluffychat/gruppechat/change_notices.dart';
import 'package:fluffychat/gruppechat/matrix_group.dart';
import 'package:fluffychat/gruppechat/screenshot_block.dart';
import 'package:fluffychat/gruppechat/user_ids.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/file_description.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:flutter/services.dart';
import 'package:gruppechat_bubbles/gruppechat_bubbles.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

const _channel = MethodChannel(gruppechatBubblesChannel);

/// The type of the downloaded file.
const chatTranscriptMimeType = 'text/markdown';

/// How many events to ask for at a time while loading the history, as the
/// chat does when scrolling up.
const _historyPageSize = 100;

/// Whether the chat's settings offer to download [room]'s conversation:
/// everyone in the chat may, unless the chat blocks screenshots
/// (screenshot_block.dart). The settings page and the tests ask this.
bool gruppechatCanDownloadTranscript(Room room) =>
    room.membership == Membership.join && !gruppechatScreenshotsBlocked(room);

/// A file name for [chatName]'s conversation downloaded at [time], such as
/// `Hanne-Chat-Alice-og-Bob-2026-11-21.md`: only letters and digits from the
/// name, any other run of characters as one dash, so no file system refuses
/// it.
String chatTranscriptFileName(String chatName, DateTime time) {
  String two(int n) => n.toString().padLeft(2, '0');
  final dashes = RegExp(r'^-+|-+$');
  var name = chatName
      .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}]+', unicode: true), '-')
      .replaceAll(dashes, '');
  if (name.characters.length > 60) {
    name = name.characters.take(60).toString().replaceAll(dashes, '');
  }
  if (name.isEmpty) name = 'Chat';
  return 'Hanne-Chat-$name-${time.year}-${two(time.month)}-'
      '${two(time.day)}.md';
}

/// One item of a transcript: a message, or a line about the chat itself such
/// as someone joining.
class TranscriptItem {
  final DateTime time;

  /// Who wrote it, or null for a line about the chat.
  final String? sender;

  /// What it says, as the chat shows it. It may have several lines.
  final String text;

  /// What it answers: the message it replies to, the thread it is in.
  final String? context;

  /// Whether [text] is the app's words rather than the sender's, such as
  /// "Deleted by Bob"; it is set in italics.
  final bool note;

  final bool edited;

  const TranscriptItem({
    required this.time,
    required this.text,
    this.sender,
    this.context,
    this.note = false,
    this.edited = false,
  });

  @override
  String toString() =>
      'TranscriptItem($time, $sender, $text, $context, $note, $edited)';
}

/// [text] with the characters Markdown reads as formatting escaped, on one
/// line: for names and the app's own words, which mean no formatting.
String markdownInline(String text) => text
    .replaceAll(RegExp(r'\s*[\r\n]+\s*'), ' ')
    .replaceAllMapped(RegExp(r'[\\`*_\[\]<~#]'), (m) => '\\${m[0]}');

/// Starts of HTML, which Markdown would show as HTML rather than as text.
final _html = RegExp(r'<(?=[A-Za-z/!?])');

/// Starts of a line that Markdown reads as structure: a heading, quote,
/// list, rule, code block or reference.
final _blockStart = [
  RegExp(r'^#{1,6}(?=[ \t]|$)'),
  RegExp(r'^>'),
  RegExp(r'^[-+*](?=[ \t]|$)'),
  // Rules and the lines under a heading, and the line under a table's head
  RegExp(r'^[-|:][-|: \t]*$'),
  RegExp(r'^(?:[*_][ \t]*){3,}$'),
  RegExp(r'^=+[ \t]*$'),
  RegExp(r'^(?:`{3,}|~{3,})'),
  RegExp(r'^\[[^\]]*\]:'),
];

/// One line of a message's text as it goes into the file: it reads as the
/// text it is and never as the file's own structure. Formatting within the
/// line, such as **bold**, is left as the sender wrote it.
String markdownText(String line, {bool startsLine = true}) {
  var text = line.trimRight();
  var indent = '';
  if (startsLine) {
    // Spaces in front would make a code block; these spaces don't
    final lead = RegExp(r'^[ \t]+').stringMatch(text) ?? '';
    indent = ' ' * lead.replaceAll('\t', '    ').length;
    text = text.substring(lead.length);
    final number = RegExp(r'^\d{1,9}(?=[.)]([ \t]|$))').stringMatch(text);
    if (number != null) {
      text = '$number\\${text.substring(number.length)}';
    } else if (_blockStart.any((start) => start.hasMatch(text))) {
      text = '\\$text';
    }
  }
  return indent + text.replaceAll(_html, r'\<');
}

/// [time]'s day as a heading, such as "Fredag 20. november 2026".
String _dayHeading(DateTime time, String? locale) {
  final day = DateFormat.yMMMMEEEEd(locale).format(time);
  return day.isEmpty ? day : day[0].toUpperCase() + day.substring(1);
}

/// The date format locale for [localeName], or null for the default.
String? _dateLocale(String localeName) {
  for (final locale in [localeName, localeName.split('_').first]) {
    if (DateFormat.localeExists(locale)) return locale;
  }
  return null;
}

/// The lines of [text], without blank ones at the start and end.
List<String> _linesOf(String text) {
  final lines = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  while (lines.length > 1 && lines.first.trim().isEmpty) {
    lines.removeAt(0);
  }
  while (lines.length > 1 && lines.last.trim().isEmpty) {
    lines.removeLast();
  }
  return lines;
}

/// [item] in Markdown, with [time] as the time it shows and [editedLabel]
/// after an edited message.
String transcriptItemMarkdown(
  TranscriptItem item,
  String time,
  String editedLabel,
) {
  final lines = _linesOf(item.text);
  String italic(String text) {
    final inline = markdownInline(text.trim());
    return inline.isEmpty ? '' : '_${inline}_';
  }

  final sender = item.sender;
  if (sender == null) return '${italic(lines.join(' '))} ($time)';

  final context = item.context;
  final header =
      '**${markdownInline(sender)}** ($time'
      '${context == null ? '' : ', ${markdownInline(context)}'}):';
  final edited = item.edited ? ' ${italic(editedLabel)}' : '';
  if (item.note) return '$header ${italic(lines.join(' '))}$edited';
  if (lines.length == 1) {
    final text = markdownText(lines.single, startsLine: false).trim();
    return text.isEmpty && edited.isEmpty
        ? header
        : '$header ${text.isEmpty ? edited.trim() : '$text$edited'}';
  }

  // Several lines: a block quote under the name, each line kept apart
  final out = StringBuffer(header);
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    out.write('\n');
    if (line.trim().isEmpty) {
      out.write('>');
      continue;
    }
    final last = i == lines.length - 1;
    final lineBreak = !last && lines[i + 1].trim().isNotEmpty ? '  ' : '';
    out.write('> ${markdownText(line)}${last ? edited : lineBreak}');
  }
  return out.toString();
}

/// The Markdown file for a chat called [chatName], downloaded at
/// [downloadedAt] by [downloadedBy], with [items] oldest first under a
/// heading for each day.
String chatTranscriptMarkdown(
  L10n l10n, {
  required String chatName,
  required String downloadedBy,
  required DateTime downloadedAt,
  required List<TranscriptItem> items,
}) {
  final locale = _dateLocale(l10n.localeName);
  final clock = DateFormat('HH:mm', locale);
  final when = DateFormat.yMMMMd(locale).add_Hm().format(downloadedAt);
  final out = StringBuffer()
    ..writeln('# ${markdownInline(chatName)}')
    ..writeln()
    ..writeln(
      l10n.gruppechatTranscriptDownloaded(when, markdownInline(downloadedBy)),
    );
  DateTime? day;
  for (final item in items) {
    final itemDay = DateTime(item.time.year, item.time.month, item.time.day);
    if (itemDay != day) {
      day = itemDay;
      out
        ..writeln()
        ..writeln('## ${_dayHeading(itemDay, locale)}');
    }
    out
      ..writeln()
      ..writeln(
        transcriptItemMarkdown(item, clock.format(item.time), l10n.edited),
      );
  }
  return out.toString();
}

/// The events that show as a message in the chat, rather than as a line
/// about it (lib/pages/chat/events/message.dart).
const _messageTypes = {
  EventTypes.Message,
  EventTypes.Sticker,
  EventTypes.Encrypted,
  EventTypes.CallInvite,
  PollEventContent.startType,
};

/// Whether [event] is in the transcript: it is sent, and the chat shows it.
bool _inTranscript(Event event) =>
    event.status.isSent &&
    event.isVisibleInGui &&
    // Never the screenshot block, which the chat doesn't show either
    event.type != gruppechatScreenshotsType &&
    // As the chat: of calls, only that one was started
    (!event.type.startsWith('m.call.') || event.type == EventTypes.CallInvite);

String _nameOf(Event event, MatrixLocals i18n) =>
    event.senderFromMemoryOrFallback.groupDisplayname(i18n: i18n);

/// What a message says in the transcript, and whether those are the app's
/// words ([TranscriptItem.note]).
({String text, bool note}) _messageText(
  Event event,
  Timeline timeline,
  L10n l10n,
  MatrixLocals i18n,
) {
  if (event.redacted) {
    // As RedactionWidget in lib/pages/chat/events/message_content.dart
    final because = event.redactedBecause;
    final by = because == null
        ? l10n.user
        : because.senderFromMemoryOrFallback.groupDisplayname(i18n: i18n);
    final reason = because?.content.tryGet<String>('reason');
    return (
      text:
          '🗑️ ${reason == null ? l10n.redactedBy(by) : l10n.redactedByBecause(by, reason)}',
      note: true,
    );
  }
  if (event.type == EventTypes.Encrypted) {
    return (text: l10n.messageNotDecryptable, note: true);
  }
  if (event.type == EventTypes.CallInvite) {
    return (text: '📞 ${l10n.startedACall(_nameOf(event, i18n))}', note: true);
  }
  if (event.type == PollEventContent.startType) {
    return (text: _pollText(event, timeline, l10n, i18n), note: false);
  }

  final shown = event.getDisplayEvent(timeline);
  String file(String symbol, String label, [String? name]) {
    name ??= shown.content.tryGet<String>('filename') ?? shown.body;
    final caption = shown.fileDescription;
    return '$symbol $label: $name${caption == null ? '' : '\n$caption'}';
  }

  final String text;
  switch (shown.messageType) {
    case MessageTypes.Image:
      text = file('📷', l10n.gruppechatTranscriptPicture);
    case MessageTypes.Video:
      text = file('🎬', l10n.gruppechatTranscriptVideo);
    case MessageTypes.File:
      text = file('📎', l10n.gruppechatTranscriptFile);
    case MessageTypes.Sticker:
      text = '🖼️ ${l10n.gruppechatTranscriptSticker}: ${shown.body}';
    case MessageTypes.Audio:
      if (shown.content.tryGetMap('org.matrix.msc3245.voice') == null) {
        text = file('🎵', l10n.gruppechatTranscriptAudio);
      } else {
        final ms = shown.infoMap.tryGet<int>('duration');
        final length = ms == null
            ? ''
            : ' (${ms ~/ 60000}:${(ms ~/ 1000 % 60).toString().padLeft(2, '0')})';
        text = '🎤 ${l10n.voiceMessage}$length';
      }
    case MessageTypes.Location:
      final place = shown.content.tryGet<String>('geo_uri') ?? shown.body;
      text = '📍 ${l10n.gruppechatTranscriptLocation}: $place';
    default:
      text = shown.calcLocalizedBodyFallback(i18n, hideReply: true);
  }
  return (text: text, note: false);
}

/// A poll's question and answers, with the votes when the chat shows them.
String _pollText(Event poll, Timeline timeline, L10n l10n, MatrixLocals i18n) {
  final PollStartContent start;
  try {
    start = poll.parsedPollEventContent.pollStartContent;
  } catch (e) {
    Logs().w('Invalid poll ${poll.eventId} in the transcript', e);
    return poll.calcLocalizedBodyFallback(i18n);
  }
  final responses = poll.getPollResponses(timeline);
  // As PollWidget: the votes show once the poll has ended, unless open
  final votesShown =
      start.kind == PollKind.disclosed || poll.getPollHasBeenEnded(timeline);
  return [
    '📊 ${start.question.mText}',
    for (final answer in start.answers)
      votesShown
          ? '• ${answer.mText} – ${l10n.countVotes(responses.values.where((ids) => ids.contains(answer.id)).length)}'
          : '• ${answer.mText}',
  ].join('\n');
}

/// [event]'s text on one short line, to say what a reply answers.
String _snippet(Event event, Timeline timeline, L10n l10n, MatrixLocals i18n) {
  final text = _messageText(event, timeline, l10n, i18n).text;
  final line = text
      .split('\n')
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => '');
  return line.characters.length > 60
      ? '${line.characters.take(59).toString().trimRight()}…'
      : line;
}

/// What [event] answers: the thread it is in and the message it replies to.
String? _contextOf(
  Event event,
  Timeline timeline,
  Map<String, Event> byId,
  L10n l10n,
  MatrixLocals i18n,
) {
  Event? shown(String? eventId) {
    final target = byId[eventId];
    return target != null && _inTranscript(target) ? target : null;
  }

  final parts = <String>[];
  if (event.relationshipType == RelationshipTypes.thread) {
    final root = shown(event.relationshipEventId);
    parts.add(
      root == null
          ? l10n.gruppechatTranscriptInAThread
          : l10n.gruppechatTranscriptInThread(
              _snippet(root, timeline, l10n, i18n),
            ),
    );
  }
  // Not the quote a thread message carries for older apps
  final replyId = event.inReplyToEventId(includingFallback: false);
  if (replyId != null) {
    final target = shown(replyId);
    parts.add(
      target == null
          ? l10n.gruppechatTranscriptReplyToMessage
          : l10n.gruppechatTranscriptReplyTo(
              _nameOf(target, i18n),
              _snippet(target, timeline, l10n, i18n),
            ),
    );
  }
  return parts.isEmpty ? null : parts.join(', ');
}

/// The items of [timeline]'s transcript, oldest first, from the events it
/// holds: what the chat shows, as it shows it.
List<TranscriptItem> chatTranscriptItems(Timeline timeline, L10n l10n) {
  final i18n = MatrixLocals(l10n);
  final byId = {for (final event in timeline.events) event.eventId: event};
  final items = <TranscriptItem>[];
  for (final event in timeline.events.reversed) {
    if (!_inTranscript(event)) continue;
    final isMessage =
        _messageTypes.contains(event.type) &&
        event.messageType != EventTypes.KeyVerificationRequest;
    if (!isMessage) {
      // As StateMessage in lib/pages/chat/events/state_message.dart
      items.add(
        TranscriptItem(
          time: event.originServerTs,
          text:
              groupChangeText(event, l10n) ??
              event.calcLocalizedBodyFallback(i18n),
        ),
      );
      continue;
    }
    final (:text, :note) = _messageText(event, timeline, l10n, i18n);
    items.add(
      TranscriptItem(
        time: event.originServerTs,
        sender: _nameOf(event, i18n),
        text: text,
        note: note,
        context: event.redacted
            ? null
            : _contextOf(event, timeline, byId, l10n, i18n),
        // As the chat, which says so under the message
        edited:
            !note &&
            event.hasAggregatedEvents(timeline, RelationshipTypes.edit),
      ),
    );
  }
  return items;
}

/// When [room] was made, or null when this device doesn't know.
DateTime? _createdAt(Room room) {
  final create = room.getState(EventTypes.RoomCreate);
  return create is Event ? create.originServerTs : null;
}

/// Loads [timeline]'s whole history, page by page as scrolling up in the
/// chat does, from this device and then the server, until there is no more.
/// [onProgress] gets how far back it has come, from 0 to 1, when the chat's
/// age is known.
Future<void> loadWholeHistory(
  Timeline timeline, {
  void Function(double? progress)? onProgress,
}) async {
  final room = timeline.room;
  final createdAt = _createdAt(room);
  final start = DateTime.now();
  double? progress() {
    if (createdAt == null || timeline.events.isEmpty) return null;
    final total = start.difference(createdAt).inMilliseconds;
    if (total <= 0) return null;
    final done = start
        .difference(timeline.events.last.originServerTs)
        .inMilliseconds;
    return (done / total).clamp(0.0, 1.0);
  }

  while (timeline.canRequestHistory) {
    final count = timeline.events.length;
    final token = room.prev_batch;
    await timeline.requestHistory(historyCount: _historyPageSize);
    // What came from the server reaches the timeline through a stream
    await Future<void>.delayed(Duration.zero);
    onProgress?.call(progress());
    if (timeline.canRequestHistory &&
        timeline.events.length == count &&
        room.prev_batch == token) {
      // Nothing came, and asking again won't change that
      Logs().w('The history of ${room.id} stopped loading at $count events');
      break;
    }
  }
}

/// Decrypts the messages of [timeline] that are still locked with the keys
/// this device can get: those it has, and those in chat backup when it is
/// unlocked here. Other devices aren't asked, as they may not answer.
Future<void> _decryptWhatThisDeviceCan(Timeline timeline) async {
  final room = timeline.room;
  final encryption = room.client.encryption;
  if (encryption == null || !room.client.encryptionEnabled) return;
  bool locked(Event event) =>
      event.type == EventTypes.Encrypted && !event.redacted;

  final asked = <String>{};
  for (final event in timeline.events.where(locked).toList()) {
    final sessionId = event.content.tryGet<String>('session_id');
    if (sessionId == null || !asked.add(sessionId)) continue;
    try {
      await encryption.keyManager.maybeAutoRequest(
        room.id,
        sessionId,
        event.content.tryGet<String>('sender_key'),
        awaitRequest: true,
      );
    } catch (e, s) {
      Logs().w('Could not get the key $sessionId from chat backup', e, s);
    }
  }
  final events = timeline.events;
  for (var i = 0; i < events.length; i++) {
    if (!locked(events[i])) continue;
    final decrypted = await encryption.decryptRoomEvent(events[i]);
    if (decrypted.type == EventTypes.Encrypted) continue;
    events[i] = decrypted;
    timeline.addAggregatedEvent(decrypted);
  }
}

/// Loads the members [timeline]'s events name that this device hasn't got
/// yet, so the transcript has their names and not their IDs.
Future<void> _loadNames(Timeline timeline) async {
  final room = timeline.room;
  final userIds = <String>{
    for (final event in timeline.events) ...[
      event.senderId,
      ?event.redactedBecause?.senderId,
    ],
  };
  await Future.wait(
    userIds
        .where(
          (userId) =>
              userId.isValidMatrixIdStrict() &&
              room.getState(EventTypes.RoomMember, userId) == null,
        )
        .map((userId) => room.requestUser(userId, ignoreErrors: true)),
  );
}

/// Refuses a conversation that can't be downloaded: the chat blocks
/// screenshots (screenshot_block.dart).
class TranscriptRefused implements Exception {
  final String message;

  const TranscriptRefused(this.message);

  @override
  String toString() => message;
}

/// The Markdown file of [room]'s whole conversation, as this device can read
/// it, downloaded [now]. Loads the whole history first, which [onProgress]
/// follows (see [loadWholeHistory]). Throws [TranscriptRefused] for a chat
/// that doesn't allow it, also when its block came on meanwhile.
Future<String> buildChatTranscript(
  Room room,
  L10n l10n, {
  DateTime? now,
  void Function(double? progress)? onProgress,
}) async {
  // Opening the timeline loads who is in the chat
  final timeline = await room.getTimeline();
  try {
    await loadWholeHistory(timeline, onProgress: onProgress);
    await _decryptWhatThisDeviceCan(timeline);
    await _loadNames(timeline);
    // Who is in the chat is all known now, and its block may have come on
    if (!gruppechatCanDownloadTranscript(room)) {
      throw TranscriptRefused(l10n.gruppechatConversationBlocked);
    }
    final i18n = MatrixLocals(l10n);
    final userId = room.client.userID!;
    final me = room.unsafeGetUserFromMemoryOrFallback(userId);
    return chatTranscriptMarkdown(
      l10n,
      chatName: room.getLocalizedDisplayname(i18n),
      downloadedBy:
          '${me.groupDisplayname(i18n: i18n)} '
          '(${room.client.displayUserId(userId)})',
      downloadedAt: now ?? DateTime.now(),
      items: chatTranscriptItems(timeline, l10n),
    );
  } finally {
    timeline.cancelSubscriptions();
  }
}

/// Saves [markdown] as [fileName] and returns what to tell, or null when
/// the save was cancelled: on Android straight to Downloads, as the
/// recovery key, in the browser as a download, elsewhere where the person
/// picks.
Future<String?> _saveTranscript(
  L10n l10n,
  String fileName,
  String markdown,
) async {
  if (PlatformInfos.isAndroid) {
    final saved = await _channel.invokeMethod<String>('saveToDownloads', {
      'fileName': fileName,
      'text': markdown,
      'mimeType': chatTranscriptMimeType,
    });
    // Null before Android 10, which then gets the save dialog
    if (saved != null) {
      return l10n.gruppechatConversationSavedInDownloads(saved);
    }
  }
  final path = await FilePicker.saveFile(
    dialogTitle: l10n.gruppechatDownloadConversation,
    fileName: fileName,
    bytes: utf8.encode(markdown),
    mimeType: chatTranscriptMimeType,
  );
  // The browser downloads it at once, and says nothing back
  if (path == null && !PlatformInfos.isWeb) return null;
  return l10n.gruppechatConversationDownloaded(fileName);
}

/// Downloads [room]'s whole conversation as a Markdown file, as the chat's
/// settings do, showing how far it has come while the history loads.
Future<void> gruppechatDownloadTranscript(
  BuildContext context,
  Room room,
) async {
  final l10n = L10n.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final loaded = await showFutureLoadingDialog(
    context: context,
    title: l10n.gruppechatLoadingConversation,
    futureWithProgress: (setProgress) =>
        buildChatTranscript(room, l10n, onProgress: setProgress),
  );
  // When it failed, the dialog has said why
  final markdown = loaded.asValue?.value;
  if (markdown == null) return;
  final fileName = chatTranscriptFileName(
    room.getLocalizedDisplayname(MatrixLocals(l10n)),
    DateTime.now(),
  );
  try {
    final saved = await _saveTranscript(l10n, fileName, markdown);
    if (saved == null) return;
    messenger.showSnackBar(SnackBar(content: Text(saved), showCloseIcon: true));
  } catch (e, s) {
    Logs().w('Could not save the conversation', e, s);
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.gruppechatConversationNotSaved(e.toString())),
        showCloseIcon: true,
      ),
    );
  }
}
