// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// A stand-in for an Android phone's notification shade: it keeps what the
/// app's notifications plugin shows, until the app clears it. The real
/// shade, and how Android draws a notification, can only be seen on a phone.
class NotificationShade extends AndroidFlutterLocalNotificationsPlugin {
  /// The notifications in the shade, by id.
  final notifications = <int, ActiveNotification>{};

  /// The messages a notification in the shade shows, by id: what Android
  /// gives back to the app when it adds a new message.
  final messages = <int, MessagingStyleInformation>{};

  /// Puts a new shade in place of the phone's.
  static NotificationShade install() {
    final shade = NotificationShade();
    FlutterLocalNotificationsPlatform.instance = shade;
    return shade;
  }

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    AndroidNotificationDetails? notificationDetails,
    String? payload,
  }) async {
    notifications[id] = ActiveNotification(
      id: id,
      channelId: notificationDetails?.channelId,
      groupKey: notificationDetails?.groupKey,
      title: title,
      body: body,
      payload: payload,
    );
    final style = notificationDetails?.styleInformation;
    if (style is MessagingStyleInformation) {
      // Android keeps a copy, not the app's own list
      messages[id] = _copy(style);
    } else {
      messages.remove(id);
    }
  }

  @override
  Future<MessagingStyleInformation?> getActiveNotificationMessagingStyle({
    required int id,
    String? tag,
  }) async {
    final style = messages[id];
    return style == null ? null : _copy(style);
  }

  static MessagingStyleInformation _copy(MessagingStyleInformation style) =>
      MessagingStyleInformation(
        style.person,
        conversationTitle: style.conversationTitle,
        groupConversation: style.groupConversation,
        messages: [...?style.messages],
      );

  @override
  Future<void> cancel({required int id, String? tag}) async {
    notifications.remove(id);
    messages.remove(id);
  }

  @override
  Future<void> cancelAll() async {
    notifications.clear();
    messages.clear();
  }

  @override
  Future<List<ActiveNotification>> getActiveNotifications() async =>
      notifications.values.toList();

  /// The notification channels the person has changed in Android's
  /// settings, by id; a channel the app makes doesn't change them.
  final channels = <String, AndroidNotificationChannel>{};

  @override
  Future<List<AndroidNotificationChannel>> getNotificationChannels() async =>
      channels.values.toList();

  @override
  Future<bool> areNotificationsEnabled() async => true;

  @override
  Future<void> createNotificationChannel(
    AndroidNotificationChannel notificationChannel,
  ) async {}

  @override
  Future<void> createNotificationChannelGroup(
    AndroidNotificationChannelGroup notificationChannelGroup,
  ) async {}
}
