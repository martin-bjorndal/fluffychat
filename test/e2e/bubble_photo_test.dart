// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Bug from 1.1.41 (Martin, OnePlus 13): in a chat bubble, a picked photo was
// not sent; pressing «Send» did nothing. Each time the bubble gets the app's
// engine back, as after the photo picker, the app went to the bubble's chat
// again (lib/gruppechat/bubbles.dart). If the chat was open on a message
// (`?event=`), that built the chat anew behind the send dialog. The bubble
// itself, the photo picker and how Android hands the engine around can only
// be tried on a phone.

@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:collection/collection.dart';
import 'package:cross_file/cross_file.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/gruppechat/bubbles.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/send_file_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/test_server.dart';

void main() {
  group('Chat bubble', skip: skipWithoutTestServer, () {
    late Room aliceChat;
    late Room bobChat;
    late Timeline bobTimeline;
    late XFile picked;

    setUpAll(() async {
      final folder = await Directory.systemTemp.createTemp('boble');
      addTearDown(() => folder.delete(recursive: true));
      final file = File('${folder.path}/boble.png');
      final image = img.Image(width: 300, height: 200);
      img.fill(image, color: img.ColorRgb8(200, 80, 30));
      await file.writeAsBytes(img.encodePng(image));
      picked = XFile(file.path, mimeType: 'image/png');

      // Widget tests block the network; these talk to the test server
      HttpOverrides.global = null;
      final alice = await logIn('alice');
      final bob = await logIn('bob');
      final (mine, theirs) = await directChat(alice, bob);
      aliceChat = mine;
      bobChat = theirs;
      bobTimeline = await theirs.getTimeline();
    });
    tearDownAll(logOutEveryone);

    testWidgets('a photo picked in a bubble is sent when the bubble gets the '
        'app back', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await AppSettings.init(loadWebConfigFile: false);
      await AppSettings.reset(loadWebConfigFile: false);
      addTearDown(() => AppSettings.reset(loadWebConfigFile: false));

      // The server works in real time while the widgets move on
      Future<void> wait(bool Function() done) async {
        for (var i = 0; i < 600 && !done(); i++) {
          await tester.pump(const Duration(milliseconds: 50));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
        }
      }

      final bobsMessage = await tester.runAsync(
        () => bobChat.sendTextEvent('Sjå her'),
      );

      // The app's chat route keys the chat by its address (routes.dart)
      final router = GoRouter(
        initialLocation: '/rooms',
        routes: [
          GoRoute(
            path: '/rooms',
            builder: (_, _) => const SizedBox(),
            routes: [
              GoRoute(
                path: ':roomid',
                builder: (_, state) => Scaffold(
                  body: _BubbleChat(
                    key: ValueKey(state.uri),
                    room: aliceChat,
                    photo: picked,
                  ),
                ),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      final routes = BubbleRouteMemory();
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
        ),
      );
      // Alice is in the chat list, opens the bubble, and goes to Bob's
      // message in it
      showWindow(router, routes, null, restoreRoute: true);
      showWindow(router, routes, aliceChat.id, restoreRoute: true);
      await wait(() => find.text('Bilete').evaluate().isNotEmpty);
      expect(
        routerLocation(router),
        Uri.parse(chatLocation(aliceChat.id)).toString(),
      );
      final atMessage =
          '/${Uri(pathSegments: ['rooms', aliceChat.id], queryParameters: {'event': bobsMessage})}';
      router.go(atMessage);
      await tester.pump();

      // She picks a photo; the picker hands it back
      await tester.tap(find.text('Bilete'));
      await wait(() => find.byType(SendFileDialog).evaluate().isNotEmpty);
      final chat = tester.state<_BubbleChatState>(find.byType(_BubbleChat));

      // The bubble gets the engine back from the picker
      showWindow(router, routes, aliceChat.id, restoreRoute: true);
      await tester.pump();
      expect(find.byType(SendFileDialog), findsOneWidget);
      expect(chat.mounted, isTrue, reason: 'the chat behind stays');
      expect(routerLocation(router), atMessage);

      final l10n = L10n.of(tester.element(find.byType(SendFileDialog)));
      await tester.tap(find.text(l10n.send));
      Event? arrived() => bobTimeline.events.firstWhereOrNull(
        (e) => e.messageType == MessageTypes.Image && e.body == 'boble.png',
      );
      await wait(() => arrived() != null);
      expect(tester.takeException(), isNull);
      expect(find.byType(SendFileDialog), findsNothing);
      expect(arrived(), isNotNull, reason: 'bob gets the photo');
      await wait(() => find.byType(SnackBar).evaluate().isEmpty);
      // Back in the main window, Alice is in the chat list again
      showWindow(router, routes, null, restoreRoute: true);
      await tester.pump();
      expect(routerLocation(router), '/rooms');
      // Time-outs of the requests run out without anything left to do
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(seconds: 10));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
      }
    });
  });
}

/// Stands in for the chat page: opens the send dialog with its own context,
/// as the chat does with a photo from the picker (sendFileAction in chat.dart).
class _BubbleChat extends StatefulWidget {
  final Room room;
  final XFile photo;
  const _BubbleChat({required this.room, required this.photo, super.key});

  @override
  State<_BubbleChat> createState() => _BubbleChatState();
}

class _BubbleChatState extends State<_BubbleChat> {
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => showAdaptiveDialog<bool>(
      context: context,
      builder: (_) => SendFileDialog(
        room: widget.room,
        files: [widget.photo],
        outerContext: context,
        threadLastEventId: null,
        threadRootEventId: null,
      ),
    ),
    child: const Text('Bilete'),
  );
}
