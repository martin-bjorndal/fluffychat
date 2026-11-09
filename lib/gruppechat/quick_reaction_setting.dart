// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:shared_preferences/shared_preferences.dart';

const String _quickReactionOnWebKey = 'gruppechat.quick_reaction_on_web';

/// Turns on reacting with a double tap in the web app, once. FluffyChat
/// started it switched off everywhere but on phones, so iPhone users, who
/// use the web app, had no quick reaction. Whoever turns it off afterwards
/// keeps it off.
Future<void> gruppechatTurnOnQuickReaction(
  SharedPreferences store, {
  required bool isWeb,
  required String doubleTapToReactKey,
}) async {
  if (!isWeb || store.getBool(_quickReactionOnWebKey) == true) return;
  await store.setBool(doubleTapToReactKey, true);
  await store.setBool(_quickReactionOnWebKey, true);
}
