// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/gruppechat/read_positions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const me = '@martin:example.invalid';
  const alice = '@alice:example.invalid';
  const bob = '@bob:example.invalid';
  // carol hasn't written anything that is loaded
  const carol = '@carol:example.invalid';

  // Newest first: a reaction the list doesn't show, then three messages.
  const timeline = [r'$reaction', r'$m3', r'$m2', r'$m1'];
  const shown = {r'$m3': alice, r'$m2': me, r'$m1': bob};

  Map<String, List<String>> positions(List<(String, String)> receipts) =>
      readPositions(
        timeline: timeline,
        shown: shown,
        receipts: receipts,
        ownUserId: me,
      );

  test('readers are shown under the message they read up to', () {
    expect(positions([(bob, r'$m2')]), {
      r'$m2': [bob],
    });
  });

  test('a receipt on a hidden event moves up to the message above it', () {
    expect(positions([(bob, r'$reaction')]), {
      r'$m3': [bob],
    });
  });

  test('the receipt furthest down the chat counts', () {
    expect(positions([(bob, r'$m1'), (bob, r'$m3')]), {
      r'$m3': [bob],
    });
  });

  test('readers show under their own messages too, and I am never shown', () {
    expect(positions([(alice, r'$m3'), (me, r'$m2')]), {
      r'$m3': [alice],
    });
  });

  test('receipts for messages that are not loaded are left out', () {
    expect(positions([(carol, r'$older')]), isEmpty);
  });

  test('writing moves a reader down to what they wrote', () {
    // alice read up to my message, then wrote $m3
    expect(positions([(alice, r'$m2')]), {
      r'$m3': [alice],
    });
  });

  test('writing moves a reader whose receipt is not loaded', () {
    expect(positions([(alice, r'$older')]), {
      r'$m3': [alice],
    });
  });

  test('a newer receipt wins over what a reader wrote', () {
    expect(positions([(bob, r'$m3')]), {
      r'$m3': [bob],
    });
  });

  test('people who send no receipts are not shown, even when they write', () {
    expect(positions([]), isEmpty);
  });

  test('several readers on one message are sorted', () {
    expect(positions([(carol, r'$m2'), (bob, r'$m2')]), {
      r'$m2': [bob, carol],
    });
  });

  test('a message is read by everyone at it or further down', () {
    final read = positions([(bob, r'$m3'), (carol, r'$m2'), (alice, r'$m3')]);
    List<String> readersOfMessage(String eventId, String sender) => readersOf(
      eventId,
      timeline: timeline,
      positions: read,
      senderId: sender,
    );
    // Its sender isn't listed: alice wrote m3
    expect(readersOfMessage(r'$m3', alice), [bob]);
    expect(readersOfMessage(r'$m2', me), unorderedEquals([alice, bob, carol]));
    expect(readersOfMessage(r'$m1', bob), unorderedEquals([alice, carol]));
    expect(readersOfMessage(r'$unknown', bob), isEmpty);
  });
}
