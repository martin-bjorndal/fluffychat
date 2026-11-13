// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// On a PC, a reply button shows beside a message while the mouse is over
// it, so one can reply without first selecting the message.

import 'package:fluffychat/gruppechat/hover_reply.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const message = 'Hei Tor Helge';

void main() {
  Future<List<String>> showMessage(
    WidgetTester tester, {
    bool enabled = true,
    bool ownMessage = false,
    Widget bubble = const Text(message),
  }) async {
    final replies = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              const SizedBox(height: 200, child: Text('Elsewhere')),
              HoverReplyContainer(
                alignment: ownMessage
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                ownMessage: ownMessage,
                enabled: enabled,
                onReply: () => replies.add(message),
                child: bubble,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return replies;
  }

  Future<TestGesture> mouseAt(WidgetTester tester, Offset position) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: position);
    addTearDown(mouse.removePointer);
    await tester.pump();
    return mouse;
  }

  Future<TestGesture> mouseElsewhere(WidgetTester tester) =>
      mouseAt(tester, tester.getCenter(find.text('Elsewhere')));

  bool replyButtonShows(WidgetTester tester) => tester
      .widgetList<Visibility>(find.byType(Visibility))
      .any((v) => v.visible);

  final replyButton = find.byIcon(Icons.reply_outlined);

  testWidgets('the mouse over a message shows a reply button that replies', (
    tester,
  ) async {
    final replies = await showMessage(tester);
    final mouse = await mouseElsewhere(tester);
    expect(replyButtonShows(tester), isFalse);

    await mouse.moveTo(tester.getCenter(find.text(message)));
    await tester.pump();
    expect(replyButtonShows(tester), isTrue);
    // Other people's messages get it on the right, toward the middle
    expect(
      tester.getCenter(replyButton).dx,
      greaterThan(tester.getCenter(find.text(message)).dx),
    );

    // Moving onto the button keeps it there, and pressing it replies. It
    // stays while the mouse is still there.
    await mouse.moveTo(tester.getCenter(replyButton));
    await tester.pump();
    expect(replyButtonShows(tester), isTrue);
    await tester.tap(replyButton, kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(replies, [message]);
    expect(replyButtonShows(tester), isTrue);

    await mouse.moveTo(tester.getCenter(find.text('Elsewhere')));
    await tester.pump();
    expect(replyButtonShows(tester), isFalse);
  });

  testWidgets('your own messages get the button on their left', (tester) async {
    await showMessage(tester, ownMessage: true);
    final mouse = await mouseElsewhere(tester);
    await mouse.moveTo(tester.getCenter(find.text(message)));
    await tester.pump();
    expect(replyButtonShows(tester), isTrue);
    expect(
      tester.getCenter(replyButton).dx,
      lessThan(tester.getCenter(find.text(message)).dx),
    );
  });

  testWidgets('the message doesn\'t move when the button shows', (
    tester,
  ) async {
    await showMessage(tester);
    final mouse = await mouseElsewhere(tester);
    final before = tester.getRect(find.text(message));
    await mouse.moveTo(before.center);
    await tester.pump();
    expect(replyButtonShows(tester), isTrue);
    expect(tester.getRect(find.text(message)), before);
  });

  testWidgets('no button where one can\'t reply', (tester) async {
    await showMessage(tester, enabled: false);
    final mouse = await mouseElsewhere(tester);
    await mouse.moveTo(tester.getCenter(find.text(message)));
    await tester.pump();
    expect(replyButtonShows(tester), isFalse);
  });

  testWidgets('a hidden button can\'t be pressed', (tester) async {
    final replies = await showMessage(tester);
    // With a mouse connected, the hidden button keeps its room
    await mouseElsewhere(tester);
    expect(replyButton, findsOneWidget);
    await tester.tap(replyButton, warnIfMissed: false);
    await tester.pump();
    expect(replies, isEmpty);
  });

  testWidgets('the bubble keeps its state when replying is turned off', (
    tester,
  ) async {
    // As when a message is selected, or one's own is sent
    await showMessage(tester, bubble: const _Counter());
    await tester.tap(find.text('0'));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
    await showMessage(tester, bubble: const _Counter(), enabled: false);
    expect(find.text('1'), findsOneWidget);
  });
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int _count = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => setState(() => _count++),
    child: Text('$_count'),
  );
}
