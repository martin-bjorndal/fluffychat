// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// Pins [eventId] in [room], or unpins it when it is pinned, as the message
/// menu's pin button does. Returns the ID of the event that says so, which
/// the chat shows as a line (`pinChangeOf` in change_notices.dart).
Future<String> togglePinnedMessage(Room room, String eventId) =>
    isPinned(room, eventId)
    ? unpinMessage(room, eventId)
    : room.setPinnedEvents(room.pinnedEventIds..add(eventId));

/// Unpins [eventId] in [room], as the pinned bar's unpin button does.
/// Returns the ID of the event that says so.
Future<String> unpinMessage(Room room, String eventId) => room.setPinnedEvents(
  room.pinnedEventIds..removeWhere((id) => id == eventId),
);

/// The pinned messages of [room] for the menu behind the pinned bar,
/// newest pinned first, as the bar shows the newest. A pinned message the
/// app can't get (the server doesn't have it or won't give it) is left
/// out, rather than listed as an entry that leads nowhere or keeping the
/// menu from opening. One pinned twice is listed once.
Future<List<Event>> pinnedMessages(Room room) async {
  final events = await Future.wait(
    room.pinnedEventIds.reversed.toSet().map(
      (id) => room
          .getEventById(id)
          .then<Event?>(
            (event) => event,
            onError: (Object e) {
              Logs().w('Could not get pinned message $id', e);
              return null;
            },
          ),
    ),
  );
  return events.nonNulls.toList();
}

/// How many messages are pinned in [room], each once.
int pinnedCount(Room room) => room.pinnedEventIds.toSet().length;

/// What the pinned bar says beside the newest pinned message when there are
/// more, so people see there is a menu behind it: "3 pinned". Null for one.
String? pinnedCountText(L10n l10n, int count) =>
    count > 1 ? l10n.gruppechatPinnedCount(count) : null;

/// The pinned bar's [pinnedCountText] for [room], or null.
Widget? pinnedCountBadge(BuildContext context, Room room) {
  final text = pinnedCountText(L10n.of(context), pinnedCount(room));
  if (text == null) return null;
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Text(
      text,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: 12,
      ),
    ),
  );
}

/// What the message menu's pin button says for [eventId] in [room]:
/// "Pin to room", or "Unpin from room" when it is pinned already, as the
/// button then unpins it (togglePinnedMessage).
String pinMenuText(L10n l10n, Room room, String eventId) =>
    isPinned(room, eventId) ? l10n.gruppechatUnpinFromChat : l10n.pinMessage;

/// The pin button's icon beside [pinMenuText]: filled when [eventId] is
/// pinned, as on the pinned bar.
IconData pinMenuIcon(Room room, String eventId) =>
    isPinned(room, eventId) ? Icons.push_pin : Icons.push_pin_outlined;

/// The message menu's pin entry for [eventId] in [room]: [pinMenuIcon] and
/// [pinMenuText].
class PinMenuLabel extends StatelessWidget {
  final Room room;
  final String eventId;
  const PinMenuLabel({required this.room, required this.eventId, super.key});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: .min,
    children: [
      Icon(pinMenuIcon(room, eventId)),
      const SizedBox(width: 12),
      Text(pinMenuText(L10n.of(context), room, eventId)),
    ],
  );
}

bool isPinned(Room room, String eventId) =>
    room.pinnedEventIds.contains(eventId);
