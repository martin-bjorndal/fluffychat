// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

/// The key in a file's content that marks it as one of a series of files
/// sent together, such as several photos picked at once.
const gruppechatSeriesKey = 'im.gruppechat.series';

/// Where a file stands in a series sent together: [index] of [count], all
/// with the same [id].
typedef FileSeries = ({String id, int index, int count});

/// The content to add to each of [count] files sent together, in order:
/// what the send dialog passes as `extraContent` for each file.
///
/// The message goes once, as the caption of the first file: it goes out
/// before the other files, so a later file failing (too big, say) doesn't
/// lose it, and the first photo is the one on top. With two or more files
/// each also carries the series, with one new id, so the app can show them
/// together.
List<Map<String, Object?>?> fileSeriesContents(
  Client client, {
  required String caption,
  required int count,
}) {
  final id = client.generateUniqueTransactionId();
  final text = caption.trim();
  return [
    for (var index = 0; index < count; index++)
      if (count > 1)
        {
          if (text.isNotEmpty && index == 0) 'body': text,
          gruppechatSeriesKey: {'id': id, 'index': index, 'count': count},
        }
      else if (text.isNotEmpty)
        {'body': text}
      else
        null,
  ];
}

/// What file [index] of those sent together replies to: only the first, the
/// one with the message and on top of the stack, is the reply to
/// [inReplyTo]; the others just belong to its series.
Event? fileReplyTarget(Event? inReplyTo, int index) =>
    index == 0 ? inReplyTo : null;

extension GruppechatFileSeriesExtension on Event {
  /// The series this file was sent in, or null for a file sent on its own.
  ///
  /// Anyone can copy an id, so files belong together only when they also
  /// have the same sender. Some may be missing (deleted, or failed to send),
  /// and others' messages may come in between.
  FileSeries? get fileSeries {
    final series = content.tryGetMap<String, Object?>(gruppechatSeriesKey);
    final id = series?.tryGet<String>('id');
    final index = series?.tryGet<int>('index');
    final count = series?.tryGet<int>('count');
    if (id == null || id.isEmpty || index == null || count == null) {
      return null;
    }
    if (count < 2 || index < 0 || index >= count) return null;
    return (id: id, index: index, count: count);
  }

  /// This message's content to forward: a forwarded file stands on its own,
  /// outside the series it was sent in.
  Map<String, Object?> get forwardedContent =>
      content.copy()..remove(gruppechatSeriesKey);
}
