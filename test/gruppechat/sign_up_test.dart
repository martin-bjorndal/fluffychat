// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/gruppechat/sign_up.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const token = registrationTokenStage;
  const dummy = 'm.login.dummy';

  group('normalizeUsername', () {
    test('trims and lowercases', () {
      expect(normalizeUsername('  Martin '), 'martin');
    });

    test('accepts a whole Matrix ID', () {
      expect(normalizeUsername('@Martin:chat.example.no'), 'martin');
    });
  });

  group('nextSignUpStage', () {
    test('starts with the invite code', () {
      expect(
        nextSignUpStage([
          [token, dummy],
        ], []),
        token,
      );
    });

    test('then the confirmation step', () {
      expect(
        nextSignUpStage(
          [
            [token, dummy],
          ],
          [token],
        ),
        dummy,
      );
    });

    test('skips flows it cannot finish', () {
      expect(
        nextSignUpStage([
          ['m.login.recaptcha', dummy],
          [token, dummy],
        ], []),
        token,
      );
    });

    test('open servers only need the confirmation step', () {
      expect(
        nextSignUpStage([
          [dummy],
        ], []),
        dummy,
      );
    });

    test('gives up when every flow needs something else', () {
      expect(
        nextSignUpStage([
          ['m.login.email.identity'],
          ['m.login.recaptcha', dummy],
        ], []),
        isNull,
      );
    });
  });

  test('server errors map to the right form field', () {
    expect(signUpProblemFor('M_USER_IN_USE'), SignUpProblem.usernameTaken);
    expect(
      signUpProblemFor('M_INVALID_USERNAME'),
      SignUpProblem.invalidUsername,
    );
    expect(signUpProblemFor('M_EXCLUSIVE'), SignUpProblem.invalidUsername);
    expect(
      signUpProblemFor('M_PASSWORD_TOO_SHORT'),
      SignUpProblem.weakPassword,
    );
    expect(signUpProblemFor('M_WEAK_PASSWORD'), SignUpProblem.weakPassword);
    expect(signUpProblemFor('M_FORBIDDEN'), SignUpProblem.signUpDisabled);
    expect(signUpProblemFor('M_UNKNOWN'), SignUpProblem.other);
  });
}
