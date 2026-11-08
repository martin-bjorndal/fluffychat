// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/gruppechat/video_opening.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VideoOpening', () {
    test('an open viewer keeps its player', () async {
      final opening = VideoOpening();
      expect(
        await opening.keep('player', (_) async => fail('disposed')),
        'player',
      );
    });

    test('a viewer closed while loading drops the player', () async {
      final opening = VideoOpening()..close();
      final disposed = <String>[];
      expect(
        await opening.keep('player', (player) async => disposed.add(player)),
        isNull,
      );
      expect(disposed, ['player']);
    });
  });
}
