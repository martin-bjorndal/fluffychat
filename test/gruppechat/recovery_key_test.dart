// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/gruppechat/recovery_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recovery key file names avoid characters file systems refuse', () {
    final name = recoveryKeyFileName(DateTime(2026, 11, 3, 9, 5));
    expect(name, 'Hanne-Chat-Recovery-Key-2026-11-03-0905.txt');
    expect(name, isNot(contains(':')));
  });
}
