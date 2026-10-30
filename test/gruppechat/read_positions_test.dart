// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/gruppechat/read_positions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const me = '@martin:example.invalid';
  const alice = '@alice:example.invalid';
  const bob = '@bob:example.invalid';

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

  test('nobody is shown under their own message, and I am never shown', () {
    expect(positions([(alice, r'$m3'), (me, r'$m2')]), isEmpty);
  });

  test('receipts for messages that are not loaded are left out', () {
    expect(positions([(bob, r'$older')]), isEmpty);
  });

  group('sending counts as reading', () {
    // Who sent what: bob reacted last, to alice's message.
    const senders = {r'$reaction': bob, r'$m3': alice, r'$m2': me, r'$m1': bob};

    Map<String, List<String>> positions(List<(String, String)> receipts) =>
        readPositions(
          timeline: timeline,
          shown: shown,
          receipts: receipts,
          senders: senders,
          ownUserId: me,
        );

    test('a reaction moves the reader down to the message above it', () {
      expect(positions([(bob, r'$m1')]), {
        r'$m3': [bob],
      });
    });

    test('after writing, the reader no longer shows above their message', () {
      // alice's receipt is still on my message, but she wrote $m3 after it
      expect(positions([(alice, r'$m2')]), {
        r'$m3': [bob],
      });
    });
  });

  test('several readers on one message are sorted', () {
    expect(positions([(bob, r'$m2'), (alice, r'$m2')]), {
      r'$m2': [alice, bob],
    });
  });
}
