// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/gruppechat/server_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseServerHeader', () {
    test('reads the software and version', () {
      expect(parseServerHeader('Synapse/1.161.0'), (
        name: 'Synapse',
        version: '1.161.0',
      ));
      expect(parseServerHeader('Synapse/1.161.0 (b=main)'), (
        name: 'Synapse',
        version: '1.161.0',
      ));
    });

    test('copes with a missing version or header', () {
      expect(parseServerHeader('Caddy'), (name: 'Caddy', version: null));
      expect(parseServerHeader(null), isNull);
      expect(parseServerHeader('  '), isNull);
    });
  });

  test('newestSpecVersion compares versions as numbers', () {
    expect(newestSpecVersion(['r0.6.1', 'v1.1', 'v1.12', 'v1.9']), 'v1.12');
    expect(newestSpecVersion(['r0.6.1']), isNull);
  });

  test('formatFileSize', () {
    expect(formatFileSize(100 * 1024 * 1024), '100 MB');
    expect(formatFileSize(500 * 1024), '500 KB');
  });
}
