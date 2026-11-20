// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Makes the web app's short sounds quiet while an iPhone is on silent
/// ([gruppechatAmbientSession], used by GruppechatSounds.play).
library;

import 'dart:async';

import 'web_audio_session_stub.dart'
    if (dart.library.js_interop) 'web_audio_session_browser.dart';

/// Safari plays a page's audio even with the iPhone's silent switch on,
/// unless the page's audio session (`navigator.audioSession`, Safari 17+)
/// is `'ambient'`. That holds for all the page's audio, videos, voice
/// messages and calls too, so the session is `'ambient'` only while a short
/// sound plays ([hold]), and back to `'auto'` after. Reported in 1.1.40.
class GruppechatAmbientSession {
  /// The session's type, or null where the browser has none.
  final String? Function() type;
  final void Function(String type) setType;

  GruppechatAmbientSession({required this.type, required this.setType});

  Timer? _restore;
  DateTime? _until;

  /// Makes the page's audio follow the silent switch for [duration], if
  /// its session is `'auto'`. Not during a call (`'play-and-record'`) or
  /// when something else has set it. A sound that comes meanwhile moves the
  /// end later. A timer, not the player, ends it, so a sound that never
  /// finishes can't leave the page on `'ambient'`.
  void hold(Duration duration) {
    final current = type();
    if (current == 'auto') {
      // Also if something set it back while one was held
      setType('ambient');
    } else if (_restore == null || current != 'ambient') {
      return;
    }
    final until = DateTime.now().add(duration);
    if (_until case final current? when current.isAfter(until)) return;
    _until = until;
    _restore?.cancel();
    _restore = Timer(duration, () {
      _restore = null;
      _until = null;
      // Unless someone else has changed it meanwhile
      if (type() == 'ambient') setType('auto');
    });
  }
}

/// The browser's audio session; on other platforms it has none, and
/// [GruppechatAmbientSession.hold] does nothing.
final gruppechatAmbientSession = GruppechatAmbientSession(
  type: webAudioSessionType,
  setType: setWebAudioSessionType,
);
