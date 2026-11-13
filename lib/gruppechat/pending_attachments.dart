// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

extension GruppechatPendingAttachment on Event {
  /// The event to download this message's file from.
  ///
  /// While a message is on its way, the SDK reads its file from the local
  /// cache it keeps for uploads, and gives up on the message when the file
  /// isn't there. A sticker, a forwarded photo or a changed caption never
  /// went through that cache, and a sticker has no file name, which crashed
  /// the app. Such a file is already on the server, so this is a copy of
  /// the event that the SDK downloads from there.
  Event get downloadableAttachment {
    final onServer = attachmentMxcUrl != null;
    final cached = content['filename'] is String && !onServer;
    if (status.isSent || cached) return this;
    return Event(
      status: EventStatus.sent,
      content: content,
      type: type,
      eventId: eventId,
      senderId: senderId,
      originServerTs: originServerTs,
      unsigned: unsigned,
      room: room,
      stateKey: stateKey,
      redacts: redacts,
      originalSource: originalSource,
    );
  }
}
