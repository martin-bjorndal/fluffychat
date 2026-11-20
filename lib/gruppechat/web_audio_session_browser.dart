// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// `navigator.audioSession`, which Safari has from 17; null elsewhere.
JSObject? get _session {
  final navigator = globalContext['navigator'];
  if (navigator == null || !navigator.isA<JSObject>()) return null;
  final session = (navigator as JSObject)['audioSession'];
  if (session == null || !session.isA<JSObject>()) return null;
  return session as JSObject;
}

/// The page's audio session type, or null without one.
String? webAudioSessionType() {
  try {
    final type = _session?['type'];
    if (type == null || !type.isA<JSString>()) return null;
    return (type as JSString).toDart;
  } catch (_) {
    return null;
  }
}

void setWebAudioSessionType(String type) {
  try {
    _session?['type'] = type.toJS;
  } catch (_) {
    // A browser that refuses the type plays as before
  }
}
