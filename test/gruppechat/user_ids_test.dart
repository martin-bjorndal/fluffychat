// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/gruppechat/user_ids.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const server = 'chat.xn--c-5ga.no';

  test('accounts on our server show as @name', () {
    expect(shortUserId('@anna:chat.xn--c-5ga.no', server), '@anna');
  });

  test('anyone else keeps the full Matrix ID', () {
    expect(shortUserId('@anna:matrix.org', server), '@anna:matrix.org');
    expect(
      shortUserId('@anna:chat.xn--c-5ga.no', null),
      '@anna:chat.xn--c-5ga.no',
    );
  });

  test('things that are not user IDs are left alone', () {
    expect(shortUserId('anna', server), 'anna');
  });
}
