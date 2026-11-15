// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// An e-mail address on the account, and a new password through it
// (lib/gruppechat/email_account.dart). The server e-mails links through the
// mail container (deploy/compose.yaml), here the stand-in mail server in
// tests/testserver/fake_services.py, in Norwegian
// (deploy/synapse-templates). Clicking a link is done the way a browser does
// it, through Caddy.

@Timeout(Duration(minutes: 3))
library;

import 'dart:async';

import 'package:fluffychat/gruppechat/email_account.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'utils/test_server.dart';

/// The e-mail that reached [address], once it has.
Future<Map<String, Object?>> emailTo(String address) => fetchedValue(
  'an e-mail to $address',
  () async => (await testServer.recorded(
    'emails',
  )).where((email) => (email['to'] as List).contains(address)).lastOrNull,
);

/// The link in [email], as the person sees it.
Uri linkIn(Map<String, Object?> email) {
  final links = (email['links'] as List).cast<String>();
  expect(links, hasLength(1), reason: 'the e-mail has one link');
  return Uri.parse(links.single);
}

/// Answers the server's request for the password again, as the app's dialog
/// does (lib/utils/uia_request_manager.dart).
StreamSubscription<UiaRequest> answerPasswordRequests(
  Client client,
  String password,
) => client.onUiaRequest.stream.listen((request) {
  if (request.state != UiaRequestState.waitForUser ||
      request.nextStages.isEmpty) {
    return;
  }
  expect(request.nextStages.first, AuthenticationTypes.password);
  request.completeStage(
    AuthenticationPassword(
      session: request.session,
      password: password,
      identifier: AuthenticationUserIdentifier(user: client.userID!),
    ),
  );
});

void main() {
  group('E-mail and forgotten passwords', skip: skipWithoutTestServer, () {
    late Client alice;
    late Client dana;
    late String password;
    late String address;
    final browser = testServer.httpClient();

    setUpAll(() async {
      alice = await logIn('alice');
      (dana, password) = await signUpNewAccount(alice, 'dana');
      address = '${dana.userID!.localpart}@example.com';
    });
    tearDownAll(() async {
      browser.close();
      await logOutEveryone();
    });

    test(
      'someone adds an e-mail address by clicking the link they get',
      () async {
        final link = await sendAddEmailLink(dana, address, sendAttempt: 1);

        final email = await emailTo(address);
        expect(email['subject'], 'Bekreft e-postadressen din');
        expect(email['from'], contains('noreply@'));
        expect(email['text'], contains('legge til denne e-postadressen'));
        final clicked = await browser.get(linkIn(email));
        expect(clicked.statusCode, 200);
        expect(clicked.body, contains('E-postadressen er bekreftet'));

        final answering = answerPasswordRequests(dana, password);
        addTearDown(answering.cancel);
        await addClickedEmail(dana, link);

        final addresses = await dana.getAccount3PIDs();
        expect(addresses?.map((a) => a.address), contains(address));
      },
    );

    test('a password is not changed before the link is clicked', () async {
      final phone = await newClient('dana-phone');
      final link = await sendPasswordResetLink(phone, address, sendAttempt: 1);
      await emailTo(address);
      await expectLater(
        setPasswordFromEmailLink(phone, link, 'not-clicked-123'),
        throwsA(isA<MatrixException>()),
      );
    });

    test(
      'someone who forgot the password sets a new one from the e-mail',
      () async {
        await testServer.forget('emails');
        final phone = await newClient('dana-phone');
        final link = await sendPasswordResetLink(
          phone,
          address,
          sendAttempt: 1,
        );

        final email = await emailTo(address);
        expect(email['subject'], 'Nytt passord for Hanne Chat');
        expect(email['text'], contains('nytt passord'));
        // The link opens a page that asks first, so a mail scanner that
        // follows links can't confirm it
        final url = linkIn(email);
        final page = await browser.get(url);
        expect(page.statusCode, 200);
        expect(page.body, contains('Ja, jeg vil lage nytt passord'));
        final confirmed = await browser.post(
          url,
          body: {
            for (final field in ['sid', 'token', 'client_secret'])
              field: url.queryParameters[field]!,
          },
        );
        expect(confirmed.statusCode, 200);
        expect(confirmed.body, contains('E-postadressen er bekreftet'));

        const newPassword = 'a-new-password-123';
        await setPasswordFromEmailLink(phone, link, newPassword);

        // The login page logs in with the e-mail address and the new password
        // (Login.passwordForgotten)
        await phone.login(
          LoginType.mLoginPassword,
          identifier: AuthenticationThirdPartyIdentifier(
            medium: 'email',
            address: address,
          ),
          password: newPassword,
        );
        expect(phone.userID, dana.userID);
        // The old password no longer works, and the other device stays
        // logged in
        await expectLater(
          (await newClient('dana-old')).login(
            LoginType.mLoginPassword,
            identifier: AuthenticationUserIdentifier(user: dana.userID!),
            password: password,
          ),
          throwsA(isA<MatrixException>()),
        );
        expect(await dana.getAccount3PIDs(), isNotEmpty);
      },
    );

    test('an address no account has gets no e-mail', () async {
      await testServer.forget('emails');
      final stranger = await newClient('stranger');
      await expectLater(
        sendPasswordResetLink(stranger, 'nobody@example.com', sendAttempt: 1),
        throwsA(
          isA<MatrixException>().having(
            (e) => e.errcode,
            'errcode',
            'M_THREEPID_NOT_FOUND',
          ),
        ),
      );
      expect(await testServer.recorded('emails'), isEmpty);
    });
  });
}
