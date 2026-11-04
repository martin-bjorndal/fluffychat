// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Chat backup: a new friend signs up, turns on chat backup and gets a
// recovery key, as the app's backup page does
// (lib/pages/bootstrap/view_model/bootstrap_view_model.dart). On a new
// phone, the recovery key unlocks the messages from before.

@Timeout(Duration(minutes: 4))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

import 'utils/test_server.dart';

void main() {
  group('Chat backup', skip: skipWithoutTestServer, () {
    late Client alice;
    late Client dave;
    late String davePassword;
    late Client bob;
    late Room daveChat;
    late String recoveryKey;
    late List<String> earlierMessages;

    setUpAll(() async {
      alice = await logIn('alice');
      bob = await logIn('bob');
      (dave, davePassword) = await signUpNewAccount(alice, 'dave');
    });
    tearDownAll(logOutEveryone);

    test('turning on chat backup gives a recovery key', () async {
      expect((await dave.getCryptoIdentityState()).initialized, isFalse);
      recoveryKey = await dave.initCryptoIdentity();
      expect(recoveryKey, isNotEmpty);
      final state = await dave.getCryptoIdentityState();
      expect(state.initialized, isTrue);
      expect(state.connected, isTrue);
    });

    test('messages are backed up as they are written', () async {
      final (mine, theirs) = await directChat(dave, bob);
      daveChat = mine;
      final bobTimeline = await theirs.getTimeline();
      earlierMessages = [
        (await daveChat.sendTextEvent('Før den nye telefonen'))!,
      ];
      final first = await arrives(
        bobTimeline,
        'dave\'s message',
        (e) => e.eventId == earlierMessages.first,
      );
      expect(first.body, 'Før den nye telefonen');
      earlierMessages.add(
        (await theirs.sendTextEvent('Svar fra Bob', inReplyTo: first))!,
      );
      final daveTimeline = await daveChat.getTimeline();
      await arrives(
        daveTimeline,
        'bob\'s answer',
        (e) => e.eventId == earlierMessages.last && textOf(e) == 'Svar fra Bob',
      );
    });

    test('a new phone asks for the recovery key', () async {
      final newPhone = await logIn(
        dave.userID!.localpart!,
        password: davePassword,
      );
      final state = await newPhone.getCryptoIdentityState();
      expect(state.initialized, isTrue);
      expect(state.connected, isFalse);

      // A wrong key is refused
      await expectLater(
        newPhone.restoreCryptoIdentity(
          'EsTj 3yST y93F SLpB jJsz eAXc 2XzA ygD3 w69H fGaN TKBj jXEd',
          selfSign: false,
        ),
        throwsA(isA<InvalidPassphraseException>()),
      );

      // As the app's unlock()
      await newPhone.restoreCryptoIdentity(recoveryKey, selfSign: false);
      expect((await newPhone.getCryptoIdentityState()).connected, isTrue);

      final chat = await joined(newPhone, daveChat.id);
      final timeline = await chat.getTimeline();
      for (final (eventId, text) in [
        (earlierMessages.first, 'Før den nye telefonen'),
        (earlierMessages.last, 'Svar fra Bob'),
      ]) {
        final event = await inHistory(
          timeline,
          'the earlier message',
          (e) => e.eventId == eventId,
        );
        // The keys come from the backup, so the messages decrypt
        await eventually(
          'the new phone decrypts "$text"',
          () =>
              textOf(
                timeline.events.firstWhere((e) => e.eventId == event.eventId),
              ) ==
              text,
        );
      }

      // And the new phone writes like the old one
      final bobTimeline = await bob.getRoomById(daveChat.id)!.getTimeline();
      await seesMembers(chat, [bob.userID!]);
      final eventId = await chat.sendTextEvent('Fra den nye telefonen');
      await arrives(
        bobTimeline,
        'the message from the new phone',
        (e) => e.eventId == eventId && e.body == 'Fra den nye telefonen',
      );
    });
  });
}
