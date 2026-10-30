// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/gruppechat/update_check.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // What Flutter's web build writes, and the server serves at /version.json
  const published = {
    'app_name': 'fluffychat',
    'version': '1.1.4',
    'build_number': '3571',
    'package_name': 'fluffychat',
  };

  test('reads the published version and build', () {
    final release = PublishedRelease.fromJson(published);
    expect(release?.version, '1.1.4');
    expect(release?.build, 3571);
  });

  test('a missing or broken version.json gives nothing', () {
    expect(PublishedRelease.fromJson(null), isNull);
    expect(PublishedRelease.fromJson({'version': '1.1.4'}), isNull);
    expect(PublishedRelease.fromJson('<html>'), isNull);
  });

  test('only a higher build number counts as newer', () {
    final release = PublishedRelease.fromJson(published);
    expect(isNewerRelease(release, '3570'), isTrue);
    expect(isNewerRelease(release, '3571'), isFalse);
    expect(isNewerRelease(release, '3572'), isFalse);
    expect(isNewerRelease(release, ''), isFalse);
    expect(isNewerRelease(null, '3570'), isFalse);
  });
}
