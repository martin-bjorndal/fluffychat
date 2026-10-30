// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/gruppechat/channel_mute.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const general = '!general:example.invalid';
  const games = '!games:example.invalid';

  test('wake rule IDs round-trip to the room ID', () {
    expect(roomIdFromWakeRuleId(wakeRuleId(general)), general);
    expect(roomIdFromWakeRuleId('.m.rule.master'), isNull);
    expect(roomIdFromWakeRuleId(general), isNull);
  });

  test('newly muted channels get a wake rule', () {
    final changes = wakeRuleChanges(
      mutedChannelIds: {general, games},
      existingRuleIds: ['.m.rule.master', wakeRuleId(general)],
    );
    expect(changes.add, {games});
    expect(changes.remove, isEmpty);
  });

  test('unmuted or left channels lose their wake rule', () {
    final changes = wakeRuleChanges(
      mutedChannelIds: {},
      existingRuleIds: [wakeRuleId(general), '.m.rule.suppress_notices'],
    );
    expect(changes.add, isEmpty);
    expect(changes.remove, {general});
  });

  test('other override rules are never touched', () {
    final changes = wakeRuleChanges(
      mutedChannelIds: {},
      // FluffyChat's "don't notify" rule uses the bare room ID
      existingRuleIds: [general, '.m.rule.is_user_mention'],
    );
    expect(changes.add, isEmpty);
    expect(changes.remove, isEmpty);
  });
}
