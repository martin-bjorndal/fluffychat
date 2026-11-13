// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

/// Sends [sticker], picked from a sticker or emoji pack, to [room].
Future<String?> sendSticker(
  Room room,
  ImagePackImageContent sticker, {
  String? threadRootEventId,
  String? threadLastEventId,
}) => room.sendEvent(
  {
    'body': sticker.body,
    'info': sticker.info ?? {},
    'url': sticker.url.toString(),
  },
  type: EventTypes.Sticker,
  threadRootEventId: threadRootEventId,
  threadLastEventId: threadLastEventId,
);
