// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

package com.dexterous.flutterlocalnotifications;

import android.app.Notification;
import android.content.Context;
import com.dexterous.flutterlocalnotifications.models.NotificationDetails;

/**
 * Builds a notification exactly as flutter_local_notifications' show() does,
 * so the bubbles plugin can add bubble metadata before it is posted. A bubble
 * disappears when its notification is updated without bubble metadata, so it
 * has to be there from the first post. This class lives in the notification
 * plugin's package to reach its builder.
 */
public final class GruppechatNotificationBuilder {
  private GruppechatNotificationBuilder() {}

  public static Notification build(Context context, NotificationDetails details) {
    return FlutterLocalNotificationsPlugin.createNotification(context, details);
  }
}
