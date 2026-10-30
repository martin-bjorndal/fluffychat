// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

/// [userId] the way people here know it: just `@name` for an account on
/// [server], the full Matrix ID for anyone else. The app only talks to our
/// own server, so its name is noise (and shows up as punycode).
String shortUserId(String userId, String? server) {
  final localpart = userId.localpart;
  if (localpart == null || server == null || userId.domain != server) {
    return userId;
  }
  return '@$localpart';
}

extension GruppechatUserIdExtension on Client {
  /// [userId] as the app shows it, see [shortUserId]. Copying and sharing
  /// still use the full ID, which other Matrix apps need.
  String displayUserId(String userId) => shortUserId(userId, userID?.domain);
}
