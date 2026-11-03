// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/notification_background_handler.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/string_color.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// The plugin's own mapping of notification details, so a notification posted
// with a bubble is built exactly like the ones the plugin shows itself.
// ignore: implementation_imports
import 'package:flutter_local_notifications/src/platform_specifics/android/method_channel_mappers.dart';
import 'package:gruppechat_bubbles/gruppechat_bubbles.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// Chat bubbles on Android 11 and newer: chats that open in a bubble over
/// other apps, like Messenger's chat heads.
///
/// The Android side is the gruppechat_bubbles plugin in packages/. It posts
/// message notifications with bubble metadata, and gives the app's windows
/// (the main window and each open bubble) the one Flutter engine in turn.
/// When a bubble gets the engine, the app shows that bubble's chat; when the
/// main window gets it back, the app goes back to where it was.
abstract final class GruppechatBubbles {
  static const _channel = MethodChannel(gruppechatBubblesChannel);

  /// The room of the bubble that shows the app, or null while the main
  /// window does.
  static final room = ValueNotifier<String?>(null);

  /// Whether the app shows in a bubble.
  static bool get active => room.value != null;

  /// Whether the phone can show bubbles. Known once [start] has run.
  static bool get supported => _supported ?? false;
  static bool? _supported;

  static final _routes = BubbleRouteMemory();
  static String? _locus;

  /// Follows which window shows the app. Called once at start-up.
  static Future<void> start() async {
    if (!PlatformInfos.isAndroid) return;
    _channel.setMethodCallHandler(_handleCall);
    FluffyChatApp.router.routerDelegate.addListener(_updateLocus);
    try {
      _supported = (await status()).supported;
      // The window may have got the engine before Dart was listening
      final window = await _channel.invokeMapMethod<String, Object?>('window');
      if (window != null && window['attached'] == true) _windowChanged(window);
    } catch (e, s) {
      Logs().w('Could not start chat bubbles', e, s);
    }
  }

  static Future<void> _handleCall(MethodCall call) async {
    if (call.method == 'windowChanged') {
      _windowChanged(Map<String, Object?>.from(call.arguments as Map));
    }
  }

  static void _windowChanged(Map<String, Object?> window) {
    final roomId = window['roomId'] as String?;
    final location = _location();
    final target = _routes.windowChanged(
      roomId,
      location: location,
      restoreRoute: window['restoreRoute'] != false,
    );
    room.value = roomId;
    if (target != null && target != location) {
      FluffyChatApp.router.go(target);
    }
    // A new window has no locus yet
    _locus = null;
    _updateLocus(force: true);
  }

  static String _location() {
    final router = FluffyChatApp.router;
    final matches = router.routerDelegate.currentConfiguration;
    return matches.isNotEmpty
        ? matches.uri.toString()
        : router.routeInformationProvider.value.uri.toString();
  }

  /// Tells Android which chat the main window shows, so it hides that chat's
  /// bubble meanwhile.
  static void _updateLocus({bool force = false}) {
    final roomId = active ? null : roomIdOfChatLocation(_location());
    if (roomId == _locus && !force) return;
    _locus = roomId;
    _invoke('setLocus', {'roomId': roomId});
  }

  /// What Android allows.
  static Future<BubbleStatus> status() async {
    if (!PlatformInfos.isAndroid) return const BubbleStatus.unsupported();
    try {
      return BubbleStatus.fromMap(
        await _channel.invokeMapMethod<String, Object?>('status'),
      );
    } catch (e, s) {
      Logs().w('Could not read the bubble settings', e, s);
      return const BubbleStatus.unsupported();
    }
  }

  /// Whether message notifications get a bubble: the person turned chat
  /// bubbles on, and the phone can show them.
  static Future<bool> isEnabled() async {
    if (!PlatformInfos.isAndroid || !AppSettings.gruppechatBubbles.value) {
      return false;
    }
    return _supported ??= (await status()).supported;
  }

  /// Whether a notification for [roomId] would show as a bubble right now.
  static Future<bool> canBubble(String roomId) async =>
      await _invoke<bool>('canBubble', {
        'roomId': roomId,
        'channelId': AppConfig.pushNotificationsChannelId,
      }) ??
      false;

  /// Shows a message notification. With [bubble], it goes through the
  /// bubbles plugin with bubble metadata; should that fail, it is shown the
  /// usual way, so a message is never lost.
  static Future<void> showNotification(
    FlutterLocalNotificationsPlugin plugin, {
    required int id,
    required NotificationDetails details,
    String? title,
    String? body,
    String? payload,
    required String roomId,
    Uint8List? icon,
    required bool bubble,
  }) async {
    final android = details.android;
    if (bubble && android != null) {
      // Bubbles are for when the person is elsewhere: while they use the
      // app, a chat only keeps a bubble it already has
      final usingApp =
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
          !active;
      try {
        await _channel.invokeMethod('post', {
          'notification': _notification(id, title, body, payload, android),
          'roomId': roomId,
          'icon': icon,
          'onlyIfBubbled': usingApp,
        });
        return;
      } catch (e, s) {
        Logs().w('Could not show the notification with a bubble', e, s);
      }
    }
    await plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }

  /// Opens a bubble for a chat from inside the app: shows the chat's current
  /// notification as a bubble, or posts a quiet one from [details] if it has
  /// none. The notification stays out of the shade, and the bubble opens
  /// right away over the app, which goes back to the chat list: the chat now
  /// lives in the bubble.
  static Future<void> openBubble({
    required int id,
    required String roomId,
    required Uint8List? icon,
    required Future<AndroidNotificationDetails> Function() details,
    String? payload,
  }) async {
    final bubble = {
      'roomId': roomId,
      'icon': icon,
      'autoExpand': true,
      'suppressNotification': true,
    };
    // Android hides a chat's bubble while a window shows that chat
    FluffyChatApp.router.go('/rooms');
    _locus = null;
    await _channel.invokeMethod('setLocus', {'roomId': null});
    final shown = await _channel.invokeMethod<bool>('bubbleExisting', {
      'id': id,
      ...bubble,
    });
    if (shown == true) return;
    await _channel.invokeMethod('post', {
      'notification': _notification(id, null, null, payload, await details()),
      ...bubble,
    });
  }

  /// The arguments flutter_local_notifications' show() sends to Android.
  static Map<String, Object?> _notification(
    int id,
    String? title,
    String? body,
    String? payload,
    AndroidNotificationDetails details,
  ) => {
    'id': id,
    'title': title,
    'body': body,
    'payload': payload ?? '',
    'platformSpecifics': details.toMap(),
  };

  /// Clears a chat's notification. A bubble's notification is hidden from
  /// the shade instead, since cancelling it would close the bubble.
  static Future<void> dismiss(
    FlutterLocalNotificationsPlugin plugin,
    int id,
  ) async {
    if (PlatformInfos.isAndroid) {
      try {
        await _channel.invokeMethod('dismiss', {'id': id});
        return;
      } catch (e, s) {
        Logs().w('Could not clear the notification', e, s);
      }
    }
    await plugin.cancel(id: id);
  }

  /// Clears all notifications but the ones bubbles need.
  static Future<void> dismissAll(FlutterLocalNotificationsPlugin plugin) async {
    if (PlatformInfos.isAndroid) {
      try {
        await _channel.invokeMethod('dismissAll');
        return;
      } catch (e, s) {
        Logs().w('Could not clear the notifications', e, s);
      }
    }
    await plugin.cancelAll();
  }

  /// The notifications kept only for their bubble, which aren't in the shade.
  static Future<Set<int>> hiddenNotificationIds() async {
    if (!PlatformInfos.isAndroid) return const {};
    return {...?await _invokeList<int>('hiddenIds')};
  }

  /// Message notification actions that clear their notification. With
  /// bubbles on, push_helper.dart has them leave it, and it is cleared here
  /// once the action is done, so a bubble's notification is only hidden.
  static Future<void> clearAfterAction(
    NotificationResponse response,
    FluffyChatNotificationActions action,
  ) async {
    const clearing = {
      FluffyChatNotificationActions.reply,
      FluffyChatNotificationActions.markAsRead,
      FluffyChatNotificationActions.mute,
    };
    final id = response.id;
    if (id == null || !clearing.contains(action)) return;
    await dismiss(FlutterLocalNotificationsPlugin(), id);
  }

  /// Turns bubbles back into plain notifications.
  static Future<void> removeBubbles() => _invoke('removeBubbles');

  /// Android's bubble settings for the app, or with [bubbles] false its
  /// notification settings.
  static Future<void> openSettings({bool bubbles = true}) =>
      _invoke('openSettings', {'bubbles': bubbles});

  /// Opens a bubble's chat in the main window, which closes the bubble.
  static Future<void> openInApp(String roomId) =>
      _invoke('openInApp', {'roomId': roomId});

  /// Collapses the bubble, as the back button at the chat does.
  static Future<void> collapse() => SystemNavigator.pop();

  /// A letter avatar like the app's own, drawn by Android. A bubble shows its
  /// chat's conversation shortcut picture, so rooms without a picture get
  /// one of these. Null where Android can't draw it.
  static Future<Uint8List?> placeholderAvatar(String name) async {
    if (!PlatformInfos.isAndroid) return null;
    final letters = avatarFallbackLetters(name);
    final colors = letters.colorScheme;
    return _invoke<Uint8List>('placeholderAvatar', {
      'letters': letters,
      'background': colors.primaryContainer.toARGB32(),
      'foreground': colors.onPrimaryContainer.toARGB32(),
    });
  }

  static Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } catch (e, s) {
      Logs().w('Chat bubbles: $method failed', e, s);
      return null;
    }
  }

  static Future<List<T>?> _invokeList<T>(String method) async {
    try {
      return await _channel.invokeListMethod<T>(method);
    } catch (e, s) {
      Logs().w('Chat bubbles: $method failed', e, s);
      return null;
    }
  }
}

/// Which chats Android lets the app show as bubbles.
enum BubblePreference { all, selected, none }

/// What Android allows, as the bubbles plugin reports it.
class BubbleStatus {
  /// Android 11 or newer.
  final bool supported;

  /// The phone-wide bubbles switch; null when Android doesn't say.
  final bool? enabled;

  /// Null when Android doesn't say (Android 11, unless it is all).
  final BubblePreference? preference;

  final bool notificationsEnabled;

  const BubbleStatus({
    required this.supported,
    this.enabled,
    this.preference,
    this.notificationsEnabled = true,
  });

  const BubbleStatus.unsupported() : this(supported: false);

  factory BubbleStatus.fromMap(Map<String, Object?>? map) => BubbleStatus(
    supported: map?['supported'] == true,
    enabled: map?['enabled'] as bool?,
    preference: BubblePreference.values.asNameMap()[map?['preference']],
    notificationsEnabled: map?['notificationsEnabled'] != false,
  );
}

/// What stands in the way of every chat showing as a bubble.
enum BubbleHint { notificationsOff, bubblesOff, notAllowed, onlySelected }

/// The hint the settings page shows, or null when every chat can bubble.
BubbleHint? bubbleHint(BubbleStatus status) {
  if (!status.supported) return null;
  if (!status.notificationsEnabled) return BubbleHint.notificationsOff;
  if (status.enabled == false) return BubbleHint.bubblesOff;
  return switch (status.preference) {
    BubblePreference.all => null,
    BubblePreference.selected => BubbleHint.onlySelected,
    _ => BubbleHint.notAllowed,
  };
}

/// Remembers where the main window was, to go back there when it gets the
/// engine back from a bubble.
class BubbleRouteMemory {
  String? _bubbleRoom;
  String? _mainLocation;
  bool _mainWindowSeen = false;

  /// A window got the engine: a bubble for [roomId], or the main window when
  /// [roomId] is null. [location] is where the app is. Returns where to go,
  /// or null to stay.
  String? windowChanged(
    String? roomId, {
    required String location,
    required bool restoreRoute,
  }) {
    if (roomId != null) {
      if (_bubbleRoom == null) {
        // A bubble that started the app has no main window to go back to
        _mainLocation = _mainWindowSeen ? location : null;
      }
      _bubbleRoom = roomId;
      return chatLocation(roomId);
    }
    _mainWindowSeen = true;
    if (_bubbleRoom == null) return null;
    final back = _mainLocation ?? '/rooms';
    _bubbleRoom = null;
    _mainLocation = null;
    // Otherwise the main window was opened for something that decides
    // where to go, such as a notification tap
    return restoreRoute ? back : null;
  }
}

/// Where the app shows the chat of [roomId].
String chatLocation(String roomId) => '/rooms/$roomId';

/// The room whose chat [location] shows; null for other pages.
String? roomIdOfChatLocation(String location) {
  final segments = Uri.parse(location).pathSegments;
  if (segments.length != 2 || segments.first != 'rooms') return null;
  final roomId = segments.last;
  return roomId.startsWith('!') ? roomId : null;
}

/// The letters of a placeholder avatar, picked as the app's Avatar does.
String avatarFallbackLetters(String? name) {
  final trimmed = name?.trim();
  if (trimmed == null || trimmed.isEmpty) return '@';
  final words = trimmed.split(' ');
  if (words.length <= 1) return trimmed.characters.first;
  return '${words.first.characters.first}${words.last.characters.first}';
}
