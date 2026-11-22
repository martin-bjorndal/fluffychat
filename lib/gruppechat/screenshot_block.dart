// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/gruppechat/matrix_group.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:gruppechat_bubbles/gruppechat_bubbles.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// A chat that blocks screenshots: while it is on screen, the Android app
/// keeps its window secure (FLAG_SECURE), so neither screenshots nor screen
/// recordings show it, for everyone in the chat. A browser can't do that,
/// so there the chat isn't shown at all ([GruppechatScreenshotGuard]).
///
/// Each person's block is their own room state, with their user ID as the
/// state key: `{"blocked": true}`, or empty when it is off. Matrix refuses a
/// state event whose state key starts with `@` from anyone else, so only the
/// person who turned a block on can turn it off; not even an admin can. The
/// chat is blocked while any of its members, joined or invited, has a block
/// on. A block of someone who has left no longer counts.
///
/// Turning it on or off leaves no trace in the chat: no line in the chat
/// (lib/utils/matrix_sdk_extensions/filtered_timeline_extension.dart), so not
/// in a downloaded conversation either (chat_transcript.dart), no preview in
/// the chat list (the SDK only previews messages and calls), and no push or
/// unread count (the server's push rules match no custom state type).
///
/// Who may turn one on: whoever may send this state type. In a direct chat
/// that is both people, in a group chat made in the app moderators and
/// admins (new_chat_power_levels.dart), as with disappearing messages.
const gruppechatScreenshotsType = 'im.gruppechat.screenshots';

/// Whether [userId] still counts as in [room]: joined or invited. When the
/// app doesn't know yet, as before the room's members are loaded, it counts,
/// so a chat is never shown unprotected by mistake.
bool _countsAsMember(Room room, String userId) {
  final member = room.getState(EventTypes.RoomMember, userId);
  if (member == null) return true;
  final membership = member.content['membership'];
  return membership == Membership.join.name ||
      membership == Membership.invite.name;
}

/// Who has a screenshot block on in [room], by user ID, sorted.
List<String> gruppechatScreenshotBlockers(Room room) {
  final states = room.states[gruppechatScreenshotsType];
  if (states == null) return const [];
  return [
    for (final MapEntry(key: userId, value: state) in states.entries)
      if (userId.startsWith('@') &&
          state.senderId == userId &&
          state.content['blocked'] == true &&
          _countsAsMember(room, userId))
        userId,
  ]..sort();
}

/// Whether [room] blocks screenshots.
bool gruppechatScreenshotsBlocked(Room room) =>
    gruppechatScreenshotBlockers(room).isNotEmpty;

/// Whether this user has a screenshot block on in [room].
bool gruppechatHasOwnScreenshotBlock(Room room) {
  final userId = room.client.userID;
  return userId != null &&
      room.getState(gruppechatScreenshotsType, userId)?.content['blocked'] ==
          true;
}

/// Whether this user may turn their own block in [room] on or off.
bool gruppechatCanSetScreenshotBlock(Room room) =>
    room.client.userID != null &&
    room.canChangeStateEvent(gruppechatScreenshotsType);

/// Turns this user's own screenshot block in [room] on or off, and returns
/// the ID of the state event. Someone else's stays as it is.
Future<String> gruppechatSetScreenshotBlock(Room room, bool blocked) =>
    room.client.setRoomStateWithKey(
      room.id,
      gruppechatScreenshotsType,
      room.client.userID!,
      blocked ? {'blocked': true} : <String, Object?>{},
    );

/// Whether this app keeps a chat that blocks screenshots out of them: the
/// Android app does ([GruppechatSecureWindow]). A browser can't, so there
/// such a chat isn't shown at all ([GruppechatScreenshotGuard]).
bool get gruppechatCanSecureWindow => PlatformInfos.isAndroid;

/// Whether [room]'s messages stay hidden in this app: the chat blocks
/// screenshots and the app can't keep them out of one, as in a browser.
/// Its list preview (chat_list_item.dart) is hidden everywhere already;
/// here the chat, its search, gallery and files, and what a notification
/// says are hidden too.
bool gruppechatHiddenHere(Room room, {bool? canSecureWindow}) =>
    !(canSecureWindow ?? gruppechatCanSecureWindow) &&
    gruppechatScreenshotsBlocked(room);

/// Shows [child], a page with a chat's messages, unless the chat is hidden
/// in this app ([gruppechatHiddenHere]); then a page that says it can only
/// be read in the Android app. It follows the chat's block as it changes.
class GruppechatScreenshotGuard extends StatelessWidget {
  final Room room;
  final Widget child;

  const GruppechatScreenshotGuard({
    required this.room,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) => StreamBuilder<Object?>(
    stream: room.client.onRoomState.stream.where(
      (update) =>
          update.roomId == room.id &&
          {
            gruppechatScreenshotsType,
            EventTypes.RoomMember,
          }.contains(update.state.type),
    ),
    builder: (context, _) {
      if (!gruppechatHiddenHere(room)) return child;
      final l10n = L10n.of(context);
      return Scaffold(
        key: const Key('chat_hidden_here'),
        appBar: AppBar(
          title: Text(room.getLocalizedDisplayname(MatrixLocals(l10n))),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.screenshot_outlined, size: 48),
                const SizedBox(height: 16),
                Text(l10n.gruppechatChatOnlyInApp, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                // Where the one who turned it on can turn it off
                TextButton(
                  onPressed: () => context.go('/rooms/${room.id}/details'),
                  child: Text(l10n.chatDetails),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Whether the app's window has to be secure while it shows [shown]: any of
/// them blocks screenshots.
bool gruppechatWindowSecure(Iterable<Room> shown) =>
    shown.any(gruppechatScreenshotsBlocked);

/// How the setting shows in a chat's details: on while the chat is blocked,
/// whoever turned it on. Only the one with their own block on can turn it
/// off; the others see why screenshots fail.
({bool on, bool enabled, String subtitle}) gruppechatScreenshotSwitch(
  Room room,
  L10n l10n,
) {
  final userId = room.client.userID;
  final others = [
    for (final blocker in gruppechatScreenshotBlockers(room))
      if (blocker != userId)
        room
            .unsafeGetUserFromMemoryOrFallback(blocker)
            .groupDisplayname(i18n: MatrixLocals(l10n)),
  ];
  final own = gruppechatHasOwnScreenshotBlock(room);
  final names = others.join(', ');
  final subtitle = [
    l10n.gruppechatBlockScreenshotsDescription,
    if (others.isNotEmpty)
      own
          ? l10n.gruppechatScreenshotsAlsoBlockedBy(names)
          : l10n.gruppechatScreenshotsBlockedBy(names),
  ].join('\n');
  return (
    on: own || others.isNotEmpty,
    // Someone else's block is theirs to turn off
    enabled: (own || others.isEmpty) && gruppechatCanSetScreenshotBlock(room),
    subtitle: subtitle,
  );
}

/// The setting in a chat's details.
class GruppechatScreenshotBlockTile extends StatelessWidget {
  final Room room;
  final Color? iconColor;

  const GruppechatScreenshotBlockTile(this.room, {this.iconColor, super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final state = gruppechatScreenshotSwitch(room, l10n);
    return SwitchListTile.adaptive(
      key: const Key('screenshot_block'),
      secondary: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        foregroundColor: iconColor,
        child: const Icon(Icons.screenshot_outlined),
      ),
      title: Text(l10n.gruppechatBlockScreenshots),
      subtitle: Text(state.subtitle),
      value: state.on,
      onChanged: state.enabled
          ? (blocked) => showFutureLoadingDialog(
              context: context,
              future: () => gruppechatSetScreenshotBlock(room, blocked),
            )
          : null,
    );
  }
}

/// Keeps the app's window secure while a chat that blocks screenshots is on
/// screen. Each open chat page tells it which chat it shows ([show] and
/// [hide]); what opens on top of a chat page (pictures, its details, search
/// and files) keeps it shown, since the chat page stays underneath. A
/// change of the chat's block, or of who is in it, applies at once.
///
/// On Android the gruppechat_bubbles plugin sets FLAG_SECURE on the window
/// that shows the app, the main window or a chat bubble, and sets it again
/// on each window that gets the app's engine.
abstract final class GruppechatSecureWindow {
  static const _channel = MethodChannel(gruppechatBubblesChannel);
  static final _shown = <Object, Room>{};
  static final _subscriptions = <Object, StreamSubscription<Object?>>{};
  static bool _secure = false;

  /// Whether the window is kept secure now.
  static bool get secure => _secure;

  /// [owner], a chat page, shows [room].
  static void show(Object owner, Room room) {
    _subscriptions.remove(owner)?.cancel();
    _shown[owner] = room;
    _subscriptions[owner] = room.client.onRoomState.stream
        .where(
          (update) =>
              update.roomId == room.id &&
              {
                gruppechatScreenshotsType,
                EventTypes.RoomMember,
              }.contains(update.state.type),
        )
        .listen((_) => update());
    update();
  }

  /// [owner] no longer shows a chat.
  static void hide(Object owner) {
    _subscriptions.remove(owner)?.cancel();
    if (_shown.remove(owner) != null) update();
  }

  /// Decides again, as when more of a chat's members have been loaded.
  static void update() {
    final secure = gruppechatWindowSecure(_shown.values);
    if (secure == _secure) return;
    _secure = secure;
    if (!PlatformInfos.isAndroid) return;
    _channel.invokeMethod('setSecure', {'secure': secure}).catchError((
      Object e,
      StackTrace s,
    ) {
      Logs().w('Could not ${secure ? 'block' : 'allow'} screenshots', e, s);
    });
  }
}
