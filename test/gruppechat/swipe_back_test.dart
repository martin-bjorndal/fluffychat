// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// On a phone, swiping right in a chat goes back to the chat list, unless the
// swipe starts on a message: there it replies, as before.

import 'package:fluffychat/gruppechat/swipe_back.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:swipe_to_action/swipe_to_action.dart';

Widget message(String text, SwipeDirection direction, List<String> replies) =>
    GruppechatSwipeBack.exempt(
      child: Swipeable(
        key: ValueKey(text),
        background: const SizedBox(),
        direction: direction,
        onSwipe: (_) => replies.add(text),
        child: SizedBox(height: 80, width: double.infinity, child: Text(text)),
      ),
    );

void main() {
  group('gruppechatIsSwipeBack', () {
    test('a long swipe or a fling to the right goes back', () {
      expect(
        gruppechatIsSwipeBack(distance: 120, velocity: 0, width: 400),
        isTrue,
      );
      expect(
        gruppechatIsSwipeBack(distance: 40, velocity: 900, width: 400),
        isTrue,
      );
    });
    test('a short, slow, or leftward swipe does not', () {
      expect(
        gruppechatIsSwipeBack(distance: 40, velocity: 100, width: 400),
        isFalse,
      );
      expect(
        gruppechatIsSwipeBack(distance: -200, velocity: -900, width: 400),
        isFalse,
      );
      expect(
        gruppechatIsSwipeBack(distance: 5, velocity: 2000, width: 400),
        isFalse,
      );
      expect(
        gruppechatIsSwipeBack(distance: 200, velocity: -900, width: 400),
        isFalse,
      );
      expect(
        gruppechatIsSwipeBack(distance: 200, velocity: 0, width: 0),
        isFalse,
      );
    });
    test('a long swipe that slows a little at the end still goes back', () {
      expect(
        gruppechatIsSwipeBack(distance: 250, velocity: -80, width: 400),
        isTrue,
      );
    });
  });

  Future<List<String>> openChat(
    WidgetTester tester, {
    bool enabled = true,
    TextDirection textDirection = TextDirection.ltr,
  }) async {
    final replies = <String>[];
    final router = GoRouter(
      initialLocation: '/rooms',
      routes: [
        // As lib/config/routes.dart: the chats sit in a navigator of their own
        ShellRoute(
          builder: (context, state, child) => child,
          routes: [
            GoRoute(
              path: '/rooms',
              builder: (context, state) => const Scaffold(body: Text('Chats')),
              routes: [
                GoRoute(
                  path: 'chat',
                  builder: (context, state) => Builder(
                    builder: (context) => GruppechatSwipeBack(
                      enabled: enabled,
                      onBack: () => Navigator.of(context).maybePop(),
                      child: Scaffold(
                        appBar: AppBar(title: const Text('Chat')),
                        body: Column(
                          children: [
                            // As message.dart wraps every message
                            message('Hei', SwipeDirection.startToEnd, replies),
                            // The user's own message, replied to leftwards
                            message('Mine', SwipeDirection.endToStart, replies),
                            // A message whose own swipe is off, as Swipeable
                            // does after a touch at the screen edge
                            GruppechatSwipeBack.exempt(
                              child: const SizedBox(
                                height: 80,
                                width: double.infinity,
                                child: Text('Picture'),
                              ),
                            ),
                            const Expanded(
                              child: Center(child: Text('Empty space')),
                            ),
                          ],
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
      MaterialApp.router(
        routerConfig: router,
        builder: (context, child) =>
            Directionality(textDirection: textDirection, child: child!),
      ),
    );
    router.push('/rooms/chat');
    await tester.pumpAndSettle();
    expect(find.text('Empty space'), findsOneWidget);
    return replies;
  }

  testWidgets('swiping right on empty space goes back to the chat list', (
    tester,
  ) async {
    await openChat(tester);
    await tester.drag(find.text('Empty space'), const Offset(250, 0));
    await tester.pumpAndSettle();
    expect(find.text('Chats'), findsOneWidget);
    expect(find.text('Empty space'), findsNothing);
  });

  testWidgets('swiping right on the top bar goes back too', (tester) async {
    await openChat(tester);
    await tester.fling(find.text('Chat'), const Offset(120, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.text('Chats'), findsOneWidget);
  });

  testWidgets('swiping right on a message replies and stays in the chat', (
    tester,
  ) async {
    final replies = await openChat(tester);
    await tester.drag(find.text('Hei'), const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(replies, ['Hei']);
    expect(find.text('Empty space'), findsOneWidget);
  });

  testWidgets('swiping right on an own message stays in the chat', (
    tester,
  ) async {
    final replies = await openChat(tester);
    await tester.drag(find.text('Mine'), const Offset(250, 0));
    await tester.pumpAndSettle();
    expect(replies, isEmpty);
    expect(find.text('Empty space'), findsOneWidget);
  });

  testWidgets('a swipe on a message never goes back', (tester) async {
    await openChat(tester);
    await tester.drag(find.text('Picture'), const Offset(250, 0));
    await tester.pumpAndSettle();
    expect(find.text('Empty space'), findsOneWidget);
  });

  testWidgets('a swipe from the screen edge is left to the system', (
    tester,
  ) async {
    await openChat(tester);
    final y = tester.getCenter(find.text('Empty space')).dy;
    await tester.dragFrom(Offset(4, y), const Offset(250, 0));
    await tester.pumpAndSettle();
    expect(find.text('Empty space'), findsOneWidget);
    // Android's gesture area, wider than the least strip
    tester.view.systemGestureInsets = FakeViewPadding(
      left: 90 * tester.view.devicePixelRatio,
    );
    addTearDown(tester.view.resetSystemGestureInsets);
    await tester.pump();
    await tester.dragFrom(Offset(60, y), const Offset(250, 0));
    await tester.pumpAndSettle();
    expect(find.text('Empty space'), findsOneWidget);
    // From the right edge, as Android's back swipe on that side
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    await tester.dragFrom(Offset(width - 4, y), const Offset(-250, 0));
    await tester.pumpAndSettle();
    expect(find.text('Empty space'), findsOneWidget);
    // Off the strip, it goes back
    await tester.dragFrom(Offset(120, y), const Offset(250, 0));
    await tester.pumpAndSettle();
    expect(find.text('Chats'), findsOneWidget);
  });

  testWidgets('in a right-to-left layout, swiping left goes back', (
    tester,
  ) async {
    await openChat(tester, textDirection: TextDirection.rtl);
    await tester.drag(find.text('Empty space'), const Offset(250, 0));
    await tester.pumpAndSettle();
    expect(find.text('Empty space'), findsOneWidget);
    await tester.drag(find.text('Empty space'), const Offset(-250, 0));
    await tester.pumpAndSettle();
    expect(find.text('Chats'), findsOneWidget);
  });

  testWidgets('swiping left, a short swipe or the mouse stay in the chat', (
    tester,
  ) async {
    await openChat(tester);
    await tester.drag(find.text('Empty space'), const Offset(-250, 0));
    await tester.pumpAndSettle();
    await tester.timedDrag(
      find.text('Empty space'),
      const Offset(30, 0),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.text('Empty space'),
      const Offset(250, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(find.text('Empty space'), findsOneWidget);
  });

  testWidgets('where it is turned off, swiping stays in the chat', (
    tester,
  ) async {
    await openChat(tester, enabled: false);
    await tester.drag(find.text('Empty space'), const Offset(250, 0));
    await tester.pumpAndSettle();
    expect(find.text('Empty space'), findsOneWidget);
  });

  testWidgets('turning it on and off keeps the chat as it was', (tester) async {
    final key = GlobalKey<_CounterState>();
    late StateSetter setEnabled;
    var enabled = true;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setEnabled = setState;
            return GruppechatSwipeBack(
              enabled: enabled,
              onBack: () {},
              child: _Counter(key: key),
            );
          },
        ),
      ),
    );
    key.currentState!.count = 3;
    setEnabled(() => enabled = false);
    await tester.pump();
    expect(key.currentState!.count, 3);
    setEnabled(() => enabled = true);
    await tester.pump();
    expect(key.currentState!.count, 3);
  });
}

class _Counter extends StatefulWidget {
  const _Counter({super.key});
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;
  @override
  Widget build(BuildContext context) => Text('$count');
}
