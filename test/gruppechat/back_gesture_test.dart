// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Swiping back on Android closes what is on top. The chat sits in a navigator
// of its own (a ShellRoute in lib/config/routes.dart), while pictures and
// sheets open over everything; the swipe must not reach the chat beneath.

import 'package:fluffychat/config/themes.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// A back swipe from the left edge, as Android sends it.
Future<void> swipeBack(WidgetTester tester) async {
  const codec = StandardMethodCodec();
  Future<void> send(String method, [Object? arguments]) =>
      tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/backgesture',
        codec.encodeMethodCall(MethodCall(method, arguments)),
        (_) {},
      );
  await send('startBackGesture', {
    'touchOffset': [5.0, 300.0],
    'progress': 0.0,
    'swipeEdge': 0,
  });
  await tester.pump();
  await send('updateBackGestureProgress', {
    'touchOffset': [150.0, 300.0],
    'progress': 0.4,
    'swipeEdge': 0,
  });
  await tester.pump();
  await send('commitBackGesture');
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'swiping back over a picture closes the picture, not the chat',
    variant: TargetPlatformVariant.only(TargetPlatform.android),
    (tester) async {
      MaterialPage<void> page(GoRouterState state, Widget child) =>
          MaterialPage(key: state.pageKey, child: child);
      final router = GoRouter(
        initialLocation: '/rooms/chat',
        routes: [
          ShellRoute(
            builder: (context, state, child) => child,
            routes: [
              GoRoute(
                path: '/rooms',
                pageBuilder: (context, state) =>
                    page(state, const Scaffold(body: Text('Chats'))),
                routes: [
                  GoRoute(
                    path: 'chat',
                    pageBuilder: (context, state) => page(
                      state,
                      Scaffold(
                        body: Builder(
                          // As message_content.dart opens a picture
                          builder: (context) => TextButton(
                            onPressed: () => showDialog(
                              context: context,
                              builder: (_) => const Text('Picture'),
                            ),
                            child: const Text('Chat'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        Builder(
          builder: (context) => MaterialApp.router(
            theme: FluffyThemes.buildTheme(
              context,
              Brightness.light,
              Colors.purple,
            ),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Chat'));
      await tester.pumpAndSettle();
      expect(find.text('Picture'), findsOneWidget);

      await swipeBack(tester);
      expect(find.text('Picture'), findsNothing);
      expect(find.text('Chat'), findsOneWidget);

      await swipeBack(tester);
      expect(find.text('Chats'), findsOneWidget);
    },
  );
}
