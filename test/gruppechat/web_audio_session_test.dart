// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Reported in 1.1.40: sounds in the open chat on a phone on silent. In
// Safari on an iPhone the web app's short sounds now follow the silent
// switch, by holding the page's audio session at 'ambient' while they play
// (lib/gruppechat/web_audio_session.dart). The session here is a stand-in;
// whether Safari goes quiet, and videos and calls play as before, can only
// be checked on an iPhone.

import 'package:fluffychat/gruppechat/sounds.dart';
import 'package:fluffychat/gruppechat/web_audio_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String? type;
  late List<String> set;
  late GruppechatAmbientSession session;
  const short = Duration(milliseconds: 150);

  setUp(() {
    type = 'auto';
    set = [];
    session = GruppechatAmbientSession(
      type: () => type,
      setType: (t) {
        set.add(t);
        type = t;
      },
    );
  });

  test(
    'a sound makes the page follow the silent switch until it is over',
    () async {
      session.hold(short);
      expect(type, 'ambient');
      await Future.delayed(short * 2);
      expect(type, 'auto');
      expect(set, ['ambient', 'auto']);
    },
  );

  test('a sound while one plays makes it last longer', () async {
    session.hold(short);
    await Future.delayed(short ~/ 2);
    session.hold(short * 2);
    await Future.delayed(short);
    // The first would have been over by now
    expect(type, 'ambient');
    await Future.delayed(short * 2);
    expect(type, 'auto');
    expect(set, ['ambient', 'auto']);
  });

  test('a shorter sound while a longer one plays changes nothing', () async {
    session.hold(short * 3);
    session.hold(short ~/ 3);
    await Future.delayed(short);
    expect(type, 'ambient');
    await Future.delayed(short * 3);
    expect(type, 'auto');
  });

  test('a type the page has set to something else is left as it is', () async {
    type = 'play-and-record';
    session.hold(short);
    await Future.delayed(short * 2);
    expect(set, isEmpty);
    expect(type, 'play-and-record');
  });

  test('a type someone else sets meanwhile is kept', () async {
    session.hold(short);
    type = 'playback';
    await Future.delayed(short * 2);
    expect(type, 'playback');
    expect(set, ['ambient']);
  });

  test(
    'a sound after the page was set back to auto meanwhile is held too',
    () async {
      session.hold(short * 2);
      type = 'auto';
      session.hold(short * 2);
      expect(type, 'ambient');
      await Future.delayed(short * 3);
      expect(type, 'auto');
    },
  );

  test('a browser without an audio session is left alone', () async {
    type = null;
    session.hold(short);
    await Future.delayed(short * 2);
    expect(set, isEmpty);
  });

  test('outside the browser there is no session', () {
    expect(gruppechatAmbientSession.type(), isNull);
    gruppechatAmbientSession.hold(short);
    expect(gruppechatAmbientSession.type(), isNull);
  });

  test('a call counts as audio in use; no call and no voice message not', () {
    // Safari's session reads 'auto' in a call too, so the app's call says
    expect(gruppechatAudioInUse(null, inCall: true), isTrue);
    expect(gruppechatAudioInUse(null, inCall: false), isFalse);
  });
}
