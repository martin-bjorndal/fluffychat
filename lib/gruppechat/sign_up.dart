// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

/// The sign-up step where people prove they were invited (a Synapse
/// registration token).
const String registrationTokenStage = 'm.login.registration_token';

const Set<String> _supportedStages = {
  registrationTokenStage,
  AuthenticationTypes.dummy,
};

/// Why creating an account failed, so the form can point at the right field.
enum SignUpProblem {
  missingInviteCode,
  invalidInviteCode,
  usernameTaken,
  invalidUsername,
  weakPassword,
  signUpDisabled,
  unsupported,
  other,
}

class SignUpException implements Exception {
  final SignUpProblem problem;

  /// The server's own explanation, when it gave one.
  final String? serverMessage;

  const SignUpException(this.problem, [this.serverMessage]);

  @override
  String toString() =>
      'SignUpException: ${problem.name}'
      '${serverMessage == null ? '' : ' ($serverMessage)'}';
}

/// Trims and lowercases a username, and drops a leading `@` or a `:server`
/// part, since people sometimes type their whole Matrix ID.
String normalizeUsername(String input) {
  var name = input.trim().toLowerCase();
  if (name.startsWith('@')) name = name.substring(1);
  final colon = name.indexOf(':');
  if (colon >= 0) name = name.substring(0, colon);
  return name;
}

/// [host] the way people write it: punycode labels are decoded, so
/// `chat.xn--c-5ga.no` becomes `chat.cø.no`. Labels that aren't valid
/// punycode are left as they are.
String displayHost(String host) => host.split('.').map(_decodeLabel).join('.');

String _decodeLabel(String label) {
  if (!label.toLowerCase().startsWith('xn--')) return label;
  try {
    return _decodePunycode(label.substring(4));
  } on FormatException {
    return label;
  }
}

// Punycode decoding as in RFC 3492, section 6.2.
const int _base = 36;
const int _tMin = 1;
const int _tMax = 26;

String _decodePunycode(String input) {
  final delimiter = input.lastIndexOf('-');
  final output = delimiter >= 0
      ? input.substring(0, delimiter).codeUnits.toList()
      : <int>[];
  var pos = delimiter >= 0 ? delimiter + 1 : 0;
  var n = 128;
  var i = 0;
  var bias = 72;
  while (pos < input.length) {
    final oldI = i;
    var weight = 1;
    for (var k = _base; ; k += _base) {
      if (pos >= input.length) throw const FormatException('Truncated');
      final digit = _punycodeDigit(input.codeUnitAt(pos++));
      i += digit * weight;
      final t = k <= bias
          ? _tMin
          : k >= bias + _tMax
          ? _tMax
          : k - bias;
      if (digit < t) break;
      weight *= _base - t;
    }
    final length = output.length + 1;
    bias = _adaptBias(i - oldI, length, oldI == 0);
    n += i ~/ length;
    i %= length;
    output.insert(i, n);
    i++;
  }
  return String.fromCharCodes(output);
}

int _punycodeDigit(int codeUnit) {
  if (codeUnit >= 0x30 && codeUnit <= 0x39) return codeUnit - 0x30 + 26;
  if (codeUnit >= 0x61 && codeUnit <= 0x7A) return codeUnit - 0x61;
  if (codeUnit >= 0x41 && codeUnit <= 0x5A) return codeUnit - 0x41;
  throw const FormatException('Invalid punycode digit');
}

int _adaptBias(int delta, int length, bool first) {
  delta = first ? delta ~/ 700 : delta ~/ 2;
  delta += delta ~/ length;
  var k = 0;
  while (delta > ((_base - _tMin) * _tMax) ~/ 2) {
    delta ~/= _base - _tMin;
    k += _base;
  }
  return k + ((_base - _tMin + 1) * delta) ~/ (delta + 38);
}

/// The next sign-up step to complete, or null when none of the offered flows
/// can be finished with an invite code alone.
String? nextSignUpStage(
  Iterable<List<String>> flows,
  Iterable<String> completed,
) {
  final done = completed.toSet();
  for (final stages in flows) {
    if (!stages.every(_supportedStages.contains)) continue;
    for (final stage in stages) {
      if (!done.contains(stage)) return stage;
    }
  }
  return null;
}

SignUpProblem signUpProblemFor(String errcode) => switch (errcode) {
  'M_USER_IN_USE' => SignUpProblem.usernameTaken,
  'M_INVALID_USERNAME' || 'M_EXCLUSIVE' => SignUpProblem.invalidUsername,
  'M_WEAK_PASSWORD' => SignUpProblem.weakPassword,
  final code when code.startsWith('M_PASSWORD_') => SignUpProblem.weakPassword,
  'M_FORBIDDEN' => SignUpProblem.signUpDisabled,
  _ => SignUpProblem.other,
};

/// Creates an account with an invite code and logs [client] into it.
///
/// [client] must already point at the homeserver (`checkHomeserver`). The
/// server's sign-up steps are handled here: the invite code, then the final
/// confirmation step.
Future<void> signUpWithInviteCode(
  Client client, {
  required String username,
  required String password,
  required String inviteCode,
  String? deviceName,
}) async {
  AuthenticationData? auth;
  String? submittedStage;
  // Each round completes one step; Synapse needs three rounds.
  for (var round = 0; round < 5; round++) {
    try {
      await client.register(
        username: username,
        password: password,
        initialDeviceDisplayName: deviceName,
        auth: auth,
      );
      return;
    } on MatrixException catch (e) {
      final flows = e.authenticationFlows;
      if (flows == null) {
        throw SignUpException(signUpProblemFor(e.errcode), e.errorMessage);
      }
      final completed = e.completedAuthenticationFlows;
      if (submittedStage != null && !completed.contains(submittedStage)) {
        throw SignUpException(
          submittedStage == registrationTokenStage
              ? SignUpProblem.invalidInviteCode
              : signUpProblemFor(e.errcode),
          e.errorMessage,
        );
      }
      final stage = nextSignUpStage(
        flows.map((flow) => flow.stages),
        completed,
      );
      if (stage == null) throw const SignUpException(SignUpProblem.unsupported);
      if (stage == registrationTokenStage && inviteCode.trim().isEmpty) {
        throw const SignUpException(SignUpProblem.missingInviteCode);
      }
      submittedStage = stage;
      auth = AuthenticationData(
        type: stage,
        session: e.session,
        additionalFields: stage == registrationTokenStage
            ? {'token': inviteCode.trim()}
            : null,
      );
    }
  }
  throw const SignUpException(SignUpProblem.unsupported);
}
