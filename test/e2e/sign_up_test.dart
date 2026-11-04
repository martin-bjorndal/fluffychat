// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Joining with an invite code: an admin creates codes in the app
// (lib/gruppechat/invite_codes.dart, through the two admin paths Caddy
// opens), and new friends sign up with them on the app's sign-up page
// (lib/gruppechat/sign_up.dart).

@Timeout(Duration(minutes: 3))
library;

import 'package:fluffychat/gruppechat/invite_codes.dart';
import 'package:fluffychat/gruppechat/sign_up.dart';
import 'package:fluffychat/gruppechat/user_ids.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'utils/test_server.dart';

Future<SignUpProblem?> problemOf(Future<void> Function() action) async {
  try {
    await action();
    return null;
  } on SignUpException catch (e) {
    return e.problem;
  }
}

void main() {
  group('Invite codes and signing up', skip: skipWithoutTestServer, () {
    late Client alice;
    late Client bob;
    // Fresh names on every run, so the test server can be reused
    final suffix = DateTime.now().millisecondsSinceEpoch % 100000;
    final erin = 'erin$suffix';
    final frank = 'frank$suffix';

    setUpAll(() async {
      alice = await logIn('alice');
      bob = await logIn('bob');
    });
    tearDownAll(logOutEveryone);

    test('only server admins can create invite codes', () async {
      expect(await alice.canCreateInviteCodes(), isTrue);
      expect(await bob.canCreateInviteCodes(), isFalse);
    });

    test('an invite code works once and lasts a week', () async {
      final code = await alice.createInviteCode();
      expect(
        code.expires!.difference(DateTime.now()).inHours,
        inInclusiveRange(7 * 24 - 1, 7 * 24),
      );

      final client = await newClient(erin);
      await signUpWithInviteCode(
        client,
        username: normalizeUsername(' ${erin.toUpperCase()} '),
        password: 'erins-password',
        inviteCode: code.code,
        deviceName: 'e2e sign-up',
      );
      expect(client.isLogged(), isTrue, reason: 'sign-up logs you in');
      expect(client.userID, '@$erin:${testServer.serverName}');
      expect(client.displayUserId(client.userID!), '@$erin');

      final again = await newClient(frank);
      expect(
        await problemOf(
          () => signUpWithInviteCode(
            again,
            username: frank,
            password: 'franks-password',
            inviteCode: code.code,
          ),
        ),
        SignUpProblem.invalidInviteCode,
      );
    });

    test('mistakes are explained and do not use up the code', () async {
      final code = await alice.createInviteCode();
      final client = await newClient(frank);
      Future<SignUpProblem?> attempt(String username, String inviteCode) =>
          problemOf(
            () => signUpWithInviteCode(
              client,
              username: username,
              password: 'franks-password',
              inviteCode: inviteCode,
            ),
          );

      expect(
        await attempt(frank, 'not-a-real-code'),
        SignUpProblem.invalidInviteCode,
      );
      expect(await attempt(frank, '  '), SignUpProblem.missingInviteCode);
      expect(await attempt(erin, code.code), SignUpProblem.usernameTaken);
      expect(
        await attempt('no spaces', code.code),
        SignUpProblem.invalidUsername,
      );
      expect(await attempt(frank, code.code), isNull);
      expect(client.userID, '@$frank:${testServer.serverName}');
    });

    test('a new account can log in on another device', () async {
      final elsewhere = await logIn(erin, password: 'erins-password');
      expect(elsewhere.userID, '@$erin:${testServer.serverName}');
    });
  });
}
