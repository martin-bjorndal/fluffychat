// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Wish from 1.1.45 (Karina): a ring around your profile picture. Bob picks
// one, and alice sees it around his picture; then he takes it away. How it
// looks can only be judged on a phone.

@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:fluffychat/gruppechat/avatar_ring.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'utils/test_server.dart';

void main() {
  group('Ring around the profile picture', skip: skipWithoutTestServer, () {
    const pink = Color(0xFFE91E63);
    late Client alice;
    late Client bob;
    late Client carol;

    setUpAll(() async {
      // Widget tests block the network; these talk to the test server
      HttpOverrides.global = null;
      alice = await logIn('alice');
      bob = await logIn('bob');
      carol = await logIn('carol');
      await directChat(alice, bob);
    });
    tearDownAll(logOutEveryone);

    Finder ring() => find.byKey(avatarRingKey);

    Color ringColor(WidgetTester tester) {
      final box = tester.widget<Container>(ring()).decoration as BoxDecoration;
      return (box.border as Border).top.color;
    }

    // Lets answers that came in reach the avatars, then draws again. The
    // lookups themselves run in runAsync: a request started in the test's
    // fake time would never get its answer.
    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('someone without a ring has none, and no error', (
      tester,
    ) async {
      await tester.runAsync(() async {
        expect(await avatarRingColor(alice, carol.userID!, fresh: true), null);
      });
    });

    testWidgets("a colour the app doesn't offer counts as no ring", (
      tester,
    ) async {
      await tester.runAsync(() async {
        await carol.setProfileField(carol.userID!, avatarRingField, {
          avatarRingField: 'pink',
        });
        expect(await avatarRingColor(alice, carol.userID!, fresh: true), null);
        await carol.setProfileField(carol.userID!, avatarRingField, {
          avatarRingField: 0x00000001,
        });
        expect(await avatarRingColor(alice, carol.userID!, fresh: true), null);
        await carol.deleteProfileField(carol.userID!, avatarRingField);
      });
    });

    testWidgets('bob picks a pink ring, and alice sees it around his picture; '
        'then he takes it away', (tester) async {
      await tester.runAsync(() async {
        await changeAvatarRing(bob, null, pink);
        expect(await avatarRingColor(bob, bob.userID!), pink);
      });

      // Bob's picture in alice's chat, after she has looked him up as her
      // app does
      await tester.runAsync(() => avatarRingColor(alice, bob.userID!));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Avatar(
              name: 'Bob',
              client: alice,
              presenceUserId: bob.userID,
            ),
          ),
        ),
      );
      await settle(tester);
      expect(ring(), findsOneWidget);
      expect(ringColor(tester), pink);
      // The avatar keeps its size, so nothing around it moves
      expect(tester.getSize(ring()), const Size.square(Avatar.defaultSize));

      // Bob's own picture, as in his settings, while he takes the ring away
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Avatar(name: 'Bob', client: bob, ringUserId: bob.userID),
          ),
        ),
      );
      await settle(tester);
      expect(ring(), findsOneWidget);
      await tester.runAsync(() => changeAvatarRing(bob, pink, null));
      await settle(tester);
      expect(ring(), findsNothing, reason: 'his picture on screen changes');

      // Alice still has the ring until she looks again (after an hour)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Avatar(
              name: 'Bob',
              client: alice,
              presenceUserId: bob.userID,
            ),
          ),
        ),
      );
      await settle(tester);
      expect(ring(), findsOneWidget);
      await tester.runAsync(
        () => avatarRingColor(alice, bob.userID!, fresh: true),
      );
      await settle(tester);
      expect(ring(), findsNothing, reason: 'her picture on screen changes');
    });
  });
}
