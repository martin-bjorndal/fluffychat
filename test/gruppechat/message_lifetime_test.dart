// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// How the time left of a message that disappears reads next to it, and how
// a chat's lifetime reads in its details (lib/gruppechat/message_lifetime.dart).

import 'package:fluffychat/gruppechat/message_lifetime.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the time left reads in hours, then minutes', () async {
    final l10n = await lookupL10n(const Locale('nb'));
    final now = DateTime(2026, 11, 9, 12);
    String left(Duration d) => gruppechatTimeLeft(l10n, now.add(d), now: now);
    expect(left(const Duration(hours: 5, minutes: 59)), '6 t');
    expect(left(const Duration(hours: 1)), '1 t');
    expect(left(const Duration(minutes: 59)), '59 min');
    expect(left(const Duration(seconds: 20)), '1 min');
    expect(gruppechatLifetimeLabel(l10n, null), 'Av');
    expect(
      gruppechatLifetimeLabel(l10n, const Duration(hours: 1)),
      'Etter 1 time',
    );
    expect(
      gruppechatLifetimeLabel(l10n, const Duration(hours: 24)),
      'Etter 24 timer',
    );
  });
}
