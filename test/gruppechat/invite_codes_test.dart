// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/gruppechat/invite_codes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a code works once for a week by default', () {
    final now = DateTime.utc(2026, 10, 30, 12);
    expect(inviteCodeRequest(now: now), {
      'uses_allowed': 1,
      'expiry_time': DateTime.utc(2026, 11, 6, 12).millisecondsSinceEpoch,
    });
  });

  test("Synapse's answer gives the code and its expiry", () {
    final expiry = DateTime.utc(2026, 11, 6, 12).millisecondsSinceEpoch;
    final invite = InviteCode.fromJson({
      'token': 'Abc123_-',
      'uses_allowed': 1,
      'pending': 0,
      'completed': 0,
      'expiry_time': expiry,
    });
    expect(invite.code, 'Abc123_-');
    expect(invite.expires?.millisecondsSinceEpoch, expiry);
  });

  test('an answer without a code is an error', () {
    expect(() => InviteCode.fromJson({}), throwsFormatException);
  });
}
