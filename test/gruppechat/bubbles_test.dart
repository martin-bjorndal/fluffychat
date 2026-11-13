// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/gruppechat/bubbles.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BubbleRouteMemory', () {
    test('goes back to where the main window was', () {
      final memory = BubbleRouteMemory();
      expect(
        memory.windowChanged(null, location: '/rooms', restoreRoute: true),
        isNull,
      );
      expect(
        memory.windowChanged(
          '!a:x',
          location: '/rooms/!b:x?client=c',
          restoreRoute: true,
        ),
        '/rooms/!a:x',
      );
      expect(
        memory.windowChanged(null, location: '/rooms/!a:x', restoreRoute: true),
        '/rooms/!b:x?client=c',
      );
    });

    test('stays when the main window was opened for something', () {
      final memory = BubbleRouteMemory()
        ..windowChanged(null, location: '/rooms', restoreRoute: true)
        ..windowChanged('!a:x', location: '/rooms', restoreRoute: true);
      expect(
        memory.windowChanged(
          null,
          location: '/rooms/!a:x',
          restoreRoute: false,
        ),
        isNull,
      );
      // Back to normal afterwards
      expect(
        memory.windowChanged(null, location: '/rooms/!a:x', restoreRoute: true),
        isNull,
      );
    });

    test('a bubble that started the app goes back to the chat list', () {
      final memory = BubbleRouteMemory();
      expect(
        memory.windowChanged(
          '!a:x',
          location: '/rooms/!a:x',
          restoreRoute: true,
        ),
        '/rooms/!a:x',
      );
      expect(
        memory.windowChanged(null, location: '/rooms/!a:x', restoreRoute: true),
        '/rooms',
      );
    });

    test('switching bubbles keeps where the main window was', () {
      final memory = BubbleRouteMemory()
        ..windowChanged(null, location: '/rooms/settings', restoreRoute: true);
      expect(
        memory.windowChanged(
          '!a:x',
          location: '/rooms/settings',
          restoreRoute: true,
        ),
        '/rooms/!a:x',
      );
      expect(
        memory.windowChanged(
          '!b:x',
          location: '/rooms/!a:x',
          restoreRoute: true,
        ),
        '/rooms/!b:x',
      );
      expect(
        memory.windowChanged(null, location: '/rooms/!b:x', restoreRoute: true),
        '/rooms/settings',
      );
    });
  });

  test('roomIdOfChatLocation', () {
    expect(roomIdOfChatLocation('/rooms/!a:x'), '!a:x');
    expect(roomIdOfChatLocation('/rooms/!a:x?client=c'), '!a:x');
    expect(roomIdOfChatLocation('/rooms/!a:x/details'), isNull);
    expect(roomIdOfChatLocation('/rooms/settings'), isNull);
    expect(roomIdOfChatLocation('/rooms/archive/!a:x'), isNull);
    expect(roomIdOfChatLocation('/rooms'), isNull);
    expect(roomIdOfChatLocation(chatLocation('!a:x')), '!a:x');
  });

  group('BubbleStatus', () {
    test('reads what the plugin reports', () {
      final status = BubbleStatus.fromMap({
        'supported': true,
        'enabled': true,
        'preference': 'selected',
        'notificationsEnabled': true,
      });
      expect(status.supported, isTrue);
      expect(status.enabled, isTrue);
      expect(status.preference, BubblePreference.selected);
      expect(status.notificationsEnabled, isTrue);
    });

    test('is unsupported without an answer', () {
      final status = BubbleStatus.fromMap(null);
      expect(status.supported, isFalse);
      expect(status.preference, isNull);
    });

    test('leaves out what Android 11 does not say', () {
      final status = BubbleStatus.fromMap({
        'supported': true,
        'enabled': null,
        'preference': null,
        'notificationsEnabled': true,
      });
      expect(status.enabled, isNull);
      expect(status.preference, isNull);
    });
  });

  group('bubbleHint', () {
    BubbleStatus status({
      bool? enabled = true,
      BubblePreference? preference = BubblePreference.all,
      bool notifications = true,
    }) => BubbleStatus(
      supported: true,
      enabled: enabled,
      preference: preference,
      notificationsEnabled: notifications,
    );

    test('has nothing to say when every chat can bubble', () {
      expect(bubbleHint(status()), isNull);
      expect(bubbleHint(status(enabled: null)), isNull);
      expect(bubbleHint(const BubbleStatus.unsupported()), isNull);
    });

    test('names what is in the way, most basic first', () {
      expect(
        bubbleHint(status(notifications: false, enabled: false)),
        BubbleHint.notificationsOff,
      );
      expect(bubbleHint(status(enabled: false)), BubbleHint.bubblesOff);
      expect(
        bubbleHint(status(preference: BubblePreference.selected)),
        BubbleHint.onlySelected,
      );
      expect(
        bubbleHint(status(preference: BubblePreference.none)),
        BubbleHint.notAllowed,
      );
      // Android 11 only says when all chats may bubble
      expect(bubbleHint(status(preference: null)), BubbleHint.notAllowed);
    });
  });

  // Bug from 1.1.30: with a chat open in a bubble, a message in another chat
  // opened that chat as a new bubble
  group('onlyKeepsBubbles', () {
    test('a new message starts no bubble while the app is in use, in the '
        'main window or in an open bubble', () {
      // An open bubble's window reports the app's lifecycle, like the main
      // window (SharedEngineFragment)
      expect(onlyKeepsBubbles(AppLifecycleState.resumed), true);
      // In front without focus, as under the pulled-down shade
      expect(onlyKeepsBubbles(AppLifecycleState.inactive), true);
    });

    test('a new message can start a bubble while the person is elsewhere, '
        'such as with the bubble collapsed', () {
      for (final state in [
        null,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.detached,
      ]) {
        expect(onlyKeepsBubbles(state), false, reason: '$state');
      }
    });
  });
}
