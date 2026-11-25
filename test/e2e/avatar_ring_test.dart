// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Wish from 1.1.45 (Karina): a ring around your profile picture. Bob picks
// one, and alice sees it around his picture; then he takes it away.
// From 1.1.46 also glitter rings and a Christmas ring. How they look can
// only be judged on a phone.

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

    // The ring bob's avatar has on screen, or null
    AvatarRingLook? ring(WidgetTester tester) {
      final painter = tester
          .widget<CustomPaint>(find.byKey(avatarRingKey))
          .foregroundPainter;
      return painter is AvatarRingPainter ? painter.look : null;
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
        expect(await avatarRingLook(alice, carol.userID!, fresh: true), null);
      });
    });

    testWidgets("a colour the app doesn't offer counts as no ring", (
      tester,
    ) async {
      await tester.runAsync(() async {
        await carol.setProfileField(carol.userID!, avatarRingField, {
          avatarRingField: 'pink',
        });
        expect(await avatarRingLook(alice, carol.userID!, fresh: true), null);
        await carol.setProfileField(carol.userID!, avatarRingField, {
          avatarRingField: 0x00000001,
        });
        expect(await avatarRingLook(alice, carol.userID!, fresh: true), null);
        await carol.deleteProfileField(carol.userID!, avatarRingField);
      });
    });

    testWidgets('bob picks a pink ring, and alice sees it around his picture; '
        'then he takes it away', (tester) async {
      await tester.runAsync(() async {
        await changeAvatarRing(bob, null, const AvatarRingLook(pink));
        expect(
          await avatarRingLook(bob, bob.userID!),
          const AvatarRingLook(pink),
        );
      });

      // Bob's picture in alice's chat, after she has looked him up as her
      // app does
      await tester.runAsync(() => avatarRingLook(alice, bob.userID!));
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
      expect(ring(tester), const AvatarRingLook(pink));
      // The avatar keeps its size, so nothing around it moves
      expect(
        tester.getSize(find.byKey(avatarRingKey)),
        const Size.square(Avatar.defaultSize),
      );

      // Bob's own picture, as in his settings, while he takes the ring away
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Avatar(name: 'Bob', client: bob, ringUserId: bob.userID),
          ),
        ),
      );
      await settle(tester);
      expect(ring(tester), isNotNull);
      await tester.runAsync(
        () => changeAvatarRing(bob, const AvatarRingLook(pink), null),
      );
      await settle(tester);
      expect(ring(tester), isNull, reason: 'his picture on screen changes');

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
      expect(ring(tester), isNotNull);
      await tester.runAsync(
        () => avatarRingLook(alice, bob.userID!, fresh: true),
      );
      await settle(tester);
      expect(ring(tester), isNull, reason: 'her picture on screen changes');
    });

    // Wish from 1.1.46 (Karina): rings with glitter, and a Christmas ring
    testWidgets('bob picks a pink glitter ring and then the Christmas ring; '
        'alice sees each, and an older app sees a plain ring', (tester) async {
      const glitter = AvatarRingLook(pink, AvatarRingKind.glitter);
      Future<Map<String, Object?>> field(String name) =>
          alice.getProfileField(bob.userID!, name);

      await tester.runAsync(() async {
        await changeAvatarRing(bob, null, glitter);
        expect(await avatarRingLook(alice, bob.userID!, fresh: true), glitter);
        // What a 1.1.45 app reads: the colour alone
        expect(avatarRingFromProfile(await field(avatarRingField)), pink);
      });
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
      expect(ring(tester), glitter);

      await tester.runAsync(() async {
        await changeAvatarRing(bob, glitter, AvatarRingLook.christmas);
        expect(
          await avatarRingLook(alice, bob.userID!, fresh: true),
          AvatarRingLook.christmas,
        );
        expect(
          avatarRingFromProfile(await field(avatarRingField)),
          AvatarRingLook.christmas.color,
          reason: 'an older app shows a red ring',
        );
      });
      await settle(tester);
      expect(
        ring(tester),
        AvatarRingLook.christmas,
        reason: 'her picture on screen changes',
      );

      // Back to a plain ring: the kind goes away
      await tester.runAsync(() async {
        await changeAvatarRing(
          bob,
          AvatarRingLook.christmas,
          const AvatarRingLook(pink),
        );
        expect(
          await avatarRingLook(alice, bob.userID!, fresh: true),
          const AvatarRingLook(pink),
        );
        await expectLater(
          field(avatarRingStyleField),
          throwsA(isA<MatrixException>()),
        );
        await changeAvatarRing(bob, const AvatarRingLook(pink), null);
        expect(await avatarRingLook(alice, bob.userID!, fresh: true), null);
      });
    });

    testWidgets(
      "a kind the app doesn't know, or a Christmas ring in another colour, is a plain ring; and a ring "
      'set by an older app (colour only) can be taken away',
      (tester) async {
        await tester.runAsync(() async {
          final me = carol.userID!;
          await carol.setProfileField(me, avatarRingField, {
            avatarRingField: pink.toARGB32(),
          });
          await carol.setProfileField(me, avatarRingStyleField, {
            avatarRingStyleField: 'rainbow',
          });
          expect(
            await avatarRingLook(alice, me, fresh: true),
            const AvatarRingLook(pink),
          );
          // A Christmas ring whose colour a 1.1.45 app has changed since
          await carol.setProfileField(me, avatarRingStyleField, {
            avatarRingStyleField: 'christmas',
          });
          expect(
            await avatarRingLook(alice, me, fresh: true),
            const AvatarRingLook(pink),
          );
          // As a 1.1.45 app leaves it: a colour and no kind
          await carol.deleteProfileField(me, avatarRingStyleField);
          await changeAvatarRing(carol, const AvatarRingLook(pink), null);
          expect(await avatarRingLook(alice, me, fresh: true), null);
        });
      },
    );
  });
}
