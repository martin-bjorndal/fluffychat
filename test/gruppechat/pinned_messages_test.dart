// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/gruppechat/pinned_messages.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import '../utils/test_client.dart';

void main() {
  test('the pinned bar counts its messages only when there are more', () async {
    final nb = await lookupL10n(const Locale('nb'));
    final en = await lookupL10n(const Locale('en'));
    expect(pinnedCountText(nb, 0), isNull);
    expect(pinnedCountText(nb, 1), isNull);
    expect(pinnedCountText(nb, 2), '2 festet');
    expect(pinnedCountText(en, 12), '12 pinned');
    expect(nb.gruppechatPinnedMessages, 'Festede meldinger');
    expect(nb.gruppechatUnpinFromChat, 'Løsne fra chat');
    expect(en.gruppechatUnpinFromChat, 'Unpin from room');
  });

  test('the message menu offers to unpin a pinned message', () async {
    final nb = await lookupL10n(const Locale('nb'));
    final room = Room(
      id: '!chat:example.invalid',
      client: await prepareTestClient(loggedIn: true),
    );
    expect(pinMenuText(nb, room, r'$a'), 'Fest til chatten');
    expect(pinMenuIcon(room, r'$a'), Icons.push_pin_outlined);
    room.setState(
      StrippedStateEvent(
        type: EventTypes.RoomPinnedEvents,
        content: {
          'pinned': [r'$a'],
        },
        senderId: '@bob:example.invalid',
        stateKey: '',
      ),
    );
    expect(pinMenuText(nb, room, r'$a'), 'Løsne fra chat');
    expect(pinMenuIcon(room, r'$a'), Icons.push_pin);
    expect(pinMenuText(nb, room, r'$b'), 'Fest til chatten');
  });
}
