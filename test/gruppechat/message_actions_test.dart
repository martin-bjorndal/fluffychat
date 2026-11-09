// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/gruppechat/message_actions.dart';
import 'package:fluffychat/gruppechat/quick_reaction_setting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/test_client.dart';

void main() {
  late Client client;
  late Room room;

  setUp(() async {
    client = await prepareTestClient(loggedIn: true);
    room = Room(id: '!room:example.invalid', client: client);
  });

  Event message({
    String? sender,
    String msgtype = MessageTypes.Text,
    EventStatus status = EventStatus.synced,
  }) => Event(
    content: {'msgtype': msgtype, 'body': 'Hei'},
    type: EventTypes.Message,
    eventId: r'$message',
    senderId: sender ?? client.userID!,
    originServerTs: DateTime(2026, 10, 30),
    room: room,
    status: status,
  );

  test('double tapping your own text message edits it', () {
    expect(message().editsOnDoubleTap, isTrue);
  });

  test('other messages keep reacting', () {
    expect(message(sender: '@alice:example.invalid').editsOnDoubleTap, isFalse);
    expect(message(msgtype: MessageTypes.Image).editsOnDoubleTap, isFalse);
    expect(message(status: EventStatus.sending).editsOnDoubleTap, isFalse);
  });

  group('quick reaction in the web app', () {
    final key = AppSettings.doubleTapToReact.key;

    Future<SharedPreferences> store(Map<String, Object> values) async {
      SharedPreferences.setMockInitialValues(values);
      return SharedPreferences.getInstance();
    }

    test('is turned on once, even where it started off', () async {
      final prefs = await store({key: false});
      await gruppechatTurnOnQuickReaction(
        prefs,
        isWeb: true,
        doubleTapToReactKey: key,
      );
      expect(prefs.getBool(key), isTrue);

      // Turned off again by the user, it stays off
      await prefs.setBool(key, false);
      await gruppechatTurnOnQuickReaction(
        prefs,
        isWeb: true,
        doubleTapToReactKey: key,
      );
      expect(prefs.getBool(key), isFalse);
    });

    test('leaves the phone app as it is', () async {
      final prefs = await store({key: false});
      await gruppechatTurnOnQuickReaction(
        prefs,
        isWeb: false,
        doubleTapToReactKey: key,
      );
      expect(prefs.getBool(key), isFalse);
    });
  });
}
