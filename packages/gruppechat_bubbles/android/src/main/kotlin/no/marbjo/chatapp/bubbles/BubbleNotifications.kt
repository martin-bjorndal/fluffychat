// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

package no.marbjo.chatapp.bubbles

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.LocusId
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.drawable.Icon
import android.os.Build
import android.provider.Settings
import android.service.notification.StatusBarNotification
import androidx.annotation.RequiresApi
import com.dexterous.flutterlocalnotifications.GruppechatNotificationBuilder
import com.dexterous.flutterlocalnotifications.models.NotificationDetails
import java.io.ByteArrayOutputStream

/** How a room's bubble shows. */
internal class Bubble(
    val roomId: String,
    /** The room's picture, if it has one. */
    val icon: ByteArray?,
    /** Opens the bubble right away; Android only does so while the app is in front. */
    val autoExpand: Boolean = false,
    /** Leaves the notification out of the notification shade. */
    val suppressNotification: Boolean = false,
    /**
     * Only keeps a bubble the chat already has, without starting a new one:
     * the person is using the app, and bubbles are for when they aren't.
     */
    val onlyIfBubbled: Boolean = false,
)

/**
 * Message notifications that can show as bubbles (Android 11+).
 *
 * A bubble lives as long as its notification, and disappears when the
 * notification is updated without bubble metadata. So while bubbles are on,
 * every message notification carries the metadata from its first post, and
 * clearing a chat's notification hides it from the shade instead of
 * cancelling it when it is a bubble.
 */
internal class BubbleNotifications(private val context: Context) {
    private val manager = context.getSystemService(NotificationManager::class.java)

    /** What Android allows, for the settings page. */
    fun status(): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return mapOf("supported" to false)
        val preference = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            when (manager.bubblePreference) {
                NotificationManager.BUBBLE_PREFERENCE_ALL -> "all"
                NotificationManager.BUBBLE_PREFERENCE_SELECTED -> "selected"
                else -> "none"
            }
        } else {
            // Android 11 only tells whether all conversations may bubble
            if (allBubblesAllowed()) "all" else null
        }
        return mapOf(
            "supported" to true,
            "enabled" to bubblesEnabled(),
            "preference" to preference,
            "notificationsEnabled" to manager.areNotificationsEnabled(),
        )
    }

    /** Whether a notification for [roomId] on [channelId] would show as a bubble. */
    fun canBubble(roomId: String, channelId: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return false
        if (!manager.areNotificationsEnabled() || bubblesEnabled() == false) return false
        // The chat's own channel once the person has changed its settings,
        // otherwise the app's channel
        val channel = manager.getNotificationChannel(channelId, roomId)
        if (channel?.importance == NotificationManager.IMPORTANCE_NONE) return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return allBubblesAllowed() || channel?.canBubble() == true
        }
        return when (manager.bubblePreference) {
            NotificationManager.BUBBLE_PREFERENCE_ALL -> true
            NotificationManager.BUBBLE_PREFERENCE_SELECTED -> channel?.canBubble() == true
            else -> false
        }
    }

    /**
     * Posts a notification from the arguments flutter_local_notifications'
     * show() takes, with bubble metadata on Android 11+.
     */
    fun post(arguments: Map<String, Any>, bubble: Bubble) {
        val details = NotificationDetails.from(arguments)
        var notification = GruppechatNotificationBuilder.build(context, details)
        val wanted = !bubble.onlyIfBubbled || active(details.id)?.isBubble == true
        if (wanted && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            notification = Notification.Builder.recoverBuilder(context, notification)
                .setBubbleMetadata(metadata(bubble))
                .setLocusId(LocusId(bubble.roomId))
                .build()
        }
        manager.notify(details.tag, details.id, notification)
    }

    /**
     * Shows the chat's current notification as a bubble. Returns false when
     * the chat has no notification.
     */
    fun bubbleExisting(id: Int, bubble: Bubble): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return false
        val current = active(id) ?: return false
        val builder = Notification.Builder.recoverBuilder(context, current.notification)
            .setBubbleMetadata(metadata(bubble))
            .setLocusId(LocusId(bubble.roomId))
            .setOnlyAlertOnce(true)
            // Quiet even when posted anew: a group's children don't alert
            // when the summary does the alerting
            .setGroupAlertBehavior(Notification.GROUP_ALERT_SUMMARY)
        if (current.notification.group == null) builder.setGroup(QUIET_GROUP)
        // An update can't bring back a bubble the person dismissed; a new
        // notification can
        if (!current.isBubble) manager.cancel(current.tag, current.id)
        manager.notify(current.tag, current.id, builder.build())
        return true
    }

    /** Clears a chat's notification, keeping it for its bubble if it has one. */
    fun dismiss(id: Int) {
        val current = active(id)
        if (current != null && keepForBubble(current)) return
        manager.cancel(id)
    }

    /** Clears all notifications but the ones bubbles need. */
    fun dismissAll() {
        for (notification in manager.activeNotifications) {
            if (!keepForBubble(notification)) manager.cancel(notification.tag, notification.id)
        }
    }

    /** Notifications kept only for their bubble, which aren't in the shade. */
    fun hiddenIds(): List<Int> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return emptyList()
        return manager.activeNotifications
            .filter { it.isBubble && it.notification.bubbleMetadata?.isNotificationSuppressed == true }
            .map { it.id }
    }

    /** Turns bubbles back into plain notifications, when the person turns bubbles off. */
    fun removeBubbles() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        for (notification in manager.activeNotifications) {
            val metadata = notification.notification.bubbleMetadata ?: continue
            if (metadata.isNotificationSuppressed) {
                // Already read, so there is nothing to keep
                manager.cancel(notification.tag, notification.id)
            } else {
                val plain = Notification.Builder.recoverBuilder(context, notification.notification)
                    .setBubbleMetadata(null)
                    .setOnlyAlertOnce(true)
                    .build()
                manager.notify(notification.tag, notification.id, plain)
            }
        }
    }

    /**
     * Hides a bubble's notification from the shade, since cancelling it would
     * close the bubble. Returns false when [notification] isn't a bubble.
     */
    private fun keepForBubble(notification: StatusBarNotification): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R || !notification.isBubble) return false
        val metadata = notification.notification.bubbleMetadata ?: return false
        if (!metadata.isNotificationSuppressed) {
            val hidden = Notification.Builder.recoverBuilder(context, notification.notification)
                .setBubbleMetadata(hidden(metadata))
                .setOnlyAlertOnce(true)
                .build()
            manager.notify(notification.tag, notification.id, hidden)
        }
        return true
    }

    private fun active(id: Int): StatusBarNotification? =
        manager.activeNotifications.firstOrNull { it.id == id && it.tag == null }

    @RequiresApi(Build.VERSION_CODES.R)
    private fun metadata(bubble: Bubble): Notification.BubbleMetadata {
        val builder = Notification.BubbleMetadata.Builder(bubbleIntent(bubble.roomId), icon(bubble.icon))
            .setDesiredHeight(DESIRED_HEIGHT_DP)
            .setAutoExpandBubble(bubble.autoExpand)
            .setSuppressNotification(bubble.suppressNotification)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Hidden while the main window shows the same chat (its locus)
            builder.setSuppressableBubble(true)
        }
        return builder.build()
    }

    /** [metadata] with its notification left out of the shade. */
    @RequiresApi(Build.VERSION_CODES.R)
    private fun hidden(metadata: Notification.BubbleMetadata): Notification.BubbleMetadata {
        val shortcutId = metadata.shortcutId
        val builder = if (shortcutId != null) {
            Notification.BubbleMetadata.Builder(shortcutId)
        } else {
            Notification.BubbleMetadata.Builder(metadata.intent!!, metadata.icon!!)
        }
        builder.setDesiredHeight(metadata.desiredHeight)
            .setDeleteIntent(metadata.deleteIntent)
            .setSuppressNotification(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setSuppressableBubble(metadata.isBubbleSuppressable)
        }
        return builder.build()
    }

    private fun bubbleIntent(roomId: String): PendingIntent {
        val intent = Intent(BubbleIntents.ACTION_BUBBLE)
            .setComponent(bubbleActivity())
            .setData(BubbleIntents.uri(roomId))
        // A bubble's intent must be mutable
        return PendingIntent.getActivity(
            context,
            roomId.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
        )
    }

    /** The app's bubble activity, found through its intent filter: it is part of the app. */
    private fun bubbleActivity(): ComponentName {
        val query = Intent(BubbleIntents.ACTION_BUBBLE).setPackage(context.packageName)
        @Suppress("DEPRECATION")
        val activity = context.packageManager.queryIntentActivities(query, 0).firstOrNull()?.activityInfo
            ?: throw IllegalStateException("The app has no activity for ${BubbleIntents.ACTION_BUBBLE}")
        return ComponentName(activity.packageName, activity.name)
    }

    /** The bubble's picture, used when the chat's shortcut has none. */
    @RequiresApi(Build.VERSION_CODES.R)
    private fun icon(bytes: ByteArray?): Icon {
        val bitmap = bytes?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
        return if (bitmap != null) {
            Icon.createWithAdaptiveBitmap(scaledDown(bitmap))
        } else {
            Icon.createWithResource(context, context.applicationInfo.icon)
        }
    }

    /** The phone-wide bubbles switch; null when it can't be read. */
    @RequiresApi(Build.VERSION_CODES.R)
    private fun bubblesEnabled(): Boolean? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) return manager.areBubblesEnabled()
        // Android 11 has no API for it, but lets apps read the setting
        return try {
            Settings.Global.getInt(context.contentResolver, "notification_bubbles") != 0
        } catch (e: Settings.SettingNotFoundException) {
            null
        }
    }

    @Suppress("DEPRECATION")
    private fun allBubblesAllowed() = manager.areBubblesAllowed()

    private companion object {
        /** As tall as Android lets a bubble be. */
        const val DESIRED_HEIGHT_DP = 1000
        const val QUIET_GROUP = "chatapp.marbjo.no.quiet"
    }
}

private val StatusBarNotification.isBubble: Boolean
    get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
        (notification.flags and Notification.FLAG_BUBBLE) != 0

/** Keeps a bubble's picture small, since it travels with every notification. */
private fun scaledDown(bitmap: Bitmap): Bitmap {
    val size = maxOf(bitmap.width, bitmap.height)
    if (size <= MAX_ICON_PX) return bitmap
    val factor = MAX_ICON_PX.toFloat() / size
    return Bitmap.createScaledBitmap(
        bitmap,
        (bitmap.width * factor).toInt().coerceAtLeast(1),
        (bitmap.height * factor).toInt().coerceAtLeast(1),
        true,
    )
}

/**
 * A letter avatar like the app's own, as a PNG laid out for an adaptive icon,
 * which Android masks to a circle. A chat's conversation shortcut gives its
 * bubble its picture, so rooms without a picture get one of these.
 */
internal fun placeholderAvatar(letters: String, background: Int, foreground: Int): ByteArray {
    val size = ADAPTIVE_ICON_PX
    val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    canvas.drawColor(background)
    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = foreground
        typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
        textAlign = Paint.Align.CENTER
        // The app's avatars size letters at 1/2.5 of the avatar, and an
        // adaptive icon shows the middle two thirds
        textSize = size * 2f / 3f / 2.5f
    }
    val baseline = size / 2f - (paint.descent() + paint.ascent()) / 2f
    canvas.drawText(letters, size / 2f, baseline, paint)
    return ByteArrayOutputStream().use { stream ->
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
        stream.toByteArray()
    }
}

private const val MAX_ICON_PX = 256

/** 108 dp at twice the baseline density. */
private const val ADAPTIVE_ICON_PX = 216
