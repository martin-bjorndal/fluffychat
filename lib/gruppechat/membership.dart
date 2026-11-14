// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

/// The room a chat page that was opened on [opened] shows, as [client]
/// knows it now.
///
/// Someone who is kicked or banned drops the room from their client, but the
/// open page and its messages keep the old [Room], which still says joined,
/// so the field for writing stayed. This marks that room as left, so that
/// everything asking it whether the user may write, react or reply says no.
Room gruppechatChatRoom(Client client, Room opened) {
  final current = client.getRoomById(opened.id);
  if (current != null) return current;
  if (opened.membership == Membership.join &&
      opened.client.getRoomById(opened.id) == null) {
    opened.membership = Membership.leave;
  }
  return opened;
}

/// Leaves [room], as "Leave" in the chat's menus does.
///
/// Someone kicked or banned is out already, and the server refuses to let
/// them leave again, which showed as "no access". When the server's list of
/// rooms they are in no longer has it, that counts as left: the room stays
/// in the archive, as the question before leaving says. Any other refusal
/// still shows.
Future<void> gruppechatLeaveRoom(Room room) async {
  try {
    await room.leave();
  } on MatrixException catch (e, s) {
    if (e.error != MatrixError.M_FORBIDDEN) rethrow;
    try {
      if (!(await room.client.getJoinedRooms()).contains(room.id)) return;
    } catch (checkError, checkStack) {
      Logs().w(
        'Could not check whether ${room.id} was left',
        checkError,
        checkStack,
      );
    }
    Error.throwWithStackTrace(e, s);
  }
}
