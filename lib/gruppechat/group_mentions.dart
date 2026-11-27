// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// @role and @alle tags in a message, marked like a @username: a username
// is sent as a link and shown as a pill, but a role or @alle is plain text,
// so the message text is searched for them with the notification matching.

import 'package:flutter/painting.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:matrix/matrix.dart';

import 'group_state.dart';
import 'matrix_group.dart';

const _linkifiers = [UrlLinkifier(), EmailLinkifier()];
const _options = LinkifyOptions(humanize: false);

/// Where [text], as shown in [room], tags one of the group's roles or
/// `@alle`: start and end of each tag. Nothing inside a web or e-mail
/// address counts. As for the notifications, a direct chat has no `@alle`,
/// and roles only when it is listed in a group's space.
List<(int, int)> gruppechatMentionRanges(Room room, String text) {
  if (!text.contains('@')) return const [];
  final everyone = !room.isDirectChat;
  final roles = GruppechatGroup.of(room)?.state.roles ?? const <GroupRole>[];
  if (!everyone && roles.isEmpty) return const [];
  final ranges = <(int, int)>[];
  var offset = 0;
  // The links LinkifySpan finds (flutter_linkify doesn't export linkify())
  var elements = <LinkifyElement>[TextElement(text)];
  for (final linkifier in _linkifiers) {
    elements = linkifier.parse(elements, _options);
  }
  for (final element in elements) {
    final piece = element.originText;
    // The pieces should add up to the text; if not, mark nothing
    if (!text.startsWith(piece, offset)) return const [];
    if (element is TextElement) {
      for (final (start, end) in groupMentionRanges(
        piece,
        roles,
        everyone: everyone,
      )) {
        ranges.add((offset + start, offset + end));
      }
    }
    offset += piece.length;
  }
  return ranges;
}

/// [text] with its role and `@alle` tags in [linkColor], underlined, like
/// a @username; [plain] shows the rest as before.
InlineSpan gruppechatMentionSpan(
  Room room,
  String text, {
  required Color? linkColor,
  required InlineSpan Function(String text) plain,
}) {
  final ranges = gruppechatMentionRanges(room, text);
  if (ranges.isEmpty) return plain(text);
  final style = TextStyle(
    color: linkColor,
    decoration: TextDecoration.underline,
    decorationColor: linkColor,
    height: 1.25,
  );
  final children = <InlineSpan>[];
  var at = 0;
  for (final (start, end) in ranges) {
    if (start > at) children.add(plain(text.substring(at, start)));
    children.add(TextSpan(text: text.substring(start, end), style: style));
    at = end;
  }
  if (at < text.length) children.add(plain(text.substring(at)));
  return TextSpan(children: children);
}
