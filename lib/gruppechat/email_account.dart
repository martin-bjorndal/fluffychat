// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// An e-mail address on the account, and a new password through it when the
// old one is forgotten. The server e-mails a link; once it has been clicked,
// the app finishes the change. Settings → Security → Change password →
// "Password recovery settings" (Settings3Pid) adds the address; "Forgot
// password" on the login page (Login) sets the new password.

import 'dart:math';

import 'package:matrix/matrix.dart';

/// A link the server has e-mailed, waiting for its owner to click it.
class EmailLink {
  final String email;
  final String clientSecret;
  final String sid;

  const EmailLink({
    required this.email,
    required this.clientSecret,
    required this.sid,
  });
}

/// A new secret for each request, which only this app knows: with it and the
/// clicked link, the server lets the app make the change.
String _newClientSecret() {
  const characters =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final random = Random.secure();
  return List.generate(
    32,
    (_) => characters[random.nextInt(characters.length)],
  ).join();
}

/// Asks the server to e-mail [email] a link that adds it to the logged-in
/// account. [sendAttempt] goes up for each new e-mail to the same address.
Future<EmailLink> sendAddEmailLink(
  Client client,
  String email, {
  required int sendAttempt,
}) async {
  final address = email.trim();
  final clientSecret = _newClientSecret();
  // Not requestTokenToRegisterEmail, which upstream used: that is for new
  // accounts, so the server sent a sign-up e-mail
  final response = await client.requestTokenTo3PIDEmail(
    clientSecret,
    address,
    sendAttempt,
  );
  return EmailLink(
    email: address,
    clientSecret: clientSecret,
    sid: response.sid,
  );
}

/// Adds the address once its link has been clicked. The server asks for the
/// password again, which the app asks for through [Client.onUiaRequest].
Future<void> addClickedEmail(Client client, EmailLink link) =>
    client.uiaRequestBackground(
      (auth) => client.add3PID(link.clientSecret, link.sid, auth: auth),
    );

/// Asks the server to e-mail [email] a link for a new password. It fails
/// with M_THREEPID_NOT_FOUND when no account has that address.
Future<EmailLink> sendPasswordResetLink(
  Client client,
  String email, {
  required int sendAttempt,
}) async {
  final address = email.trim();
  final clientSecret = _newClientSecret();
  final response = await client.requestTokenToResetPasswordEmail(
    clientSecret,
    address,
    sendAttempt,
  );
  return EmailLink(
    email: address,
    clientSecret: clientSecret,
    sid: response.sid,
  );
}

/// Sets [newPassword] once the reset link has been clicked. The account's
/// other devices stay logged in.
Future<void> setPasswordFromEmailLink(
  Client client,
  EmailLink link,
  String newPassword,
) => client.request(
  RequestType.POST,
  '/client/v3/account/password',
  data: {
    'new_password': newPassword,
    'logout_devices': false,
    'auth': AuthenticationThreePidCreds(
      type: AuthenticationTypes.emailIdentity,
      threepidCreds: ThreepidCreds(
        sid: link.sid,
        clientSecret: link.clientSecret,
      ),
    ).toJson(),
  },
);
