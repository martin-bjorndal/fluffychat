// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

package no.marbjo.chatapp.bubbles

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.LocusId
import android.os.Build
import android.os.PersistableBundle
import android.provider.MediaStore
import android.provider.Settings
import android.util.Log
import java.io.IOException
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Hanne Chat's own Android code. Mostly chat bubbles (Android 11+), plus
 * saving and copying the recovery key reliably. Posts message notifications
 * with bubble metadata (see [BubbleNotifications]) and tells Dart which
 * window shows the app's Flutter engine: the main window or a bubble.
 *
 * Flutter registers it on every engine, including the ones that handle
 * pushes and notification actions in the background, so a notification
 * never loses its bubble because it was posted from there.
 */
class GruppechatBubblesPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private lateinit var notifications: BubbleNotifications
    private var activity: Activity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        notifications = BubbleNotifications(context)
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) = attachTo(binding.activity)

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        attachTo(binding.activity)

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    /** A window got the engine: Dart shows what that window is for. */
    private fun attachTo(activity: Activity) {
        this.activity = activity
        channel.invokeMethod("windowChanged", window())
    }

    private fun window(): Map<String, Any?> {
        val window = activity as? BubbleWindow
        return mapOf(
            "attached" to (activity != null),
            "roomId" to window?.bubbleRoomId,
            "restoreRoute" to (window?.restoreRoute ?: true),
        )
    }

    /** The main window, while it has the engine. */
    private val mainWindow: Activity?
        get() = activity?.takeIf { (it as? BubbleWindow)?.bubbleRoomId == null }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "window" -> result.success(window())
                "status" -> result.success(notifications.status())
                "canBubble" -> result.success(
                    notifications.canBubble(call.string("roomId"), call.string("channelId")),
                )
                "post" -> {
                    val arguments = call.argument<Map<String, Any>>("notification")
                        ?: throw IllegalArgumentException("notification is missing")
                    notifications.post(arguments, call.bubble())
                    if (call.argument<Boolean>("minimize") == true) minimize()
                    result.success(null)
                }
                "bubbleExisting" -> {
                    val shown = notifications.bubbleExisting(call.int("id"), call.bubble())
                    if (shown && call.argument<Boolean>("minimize") == true) minimize()
                    result.success(shown)
                }
                "dismiss" -> {
                    notifications.dismiss(call.int("id"))
                    result.success(null)
                }
                "dismissAll" -> {
                    notifications.dismissAll()
                    result.success(null)
                }
                "hiddenIds" -> result.success(notifications.hiddenIds())
                "removeBubbles" -> {
                    notifications.removeBubbles()
                    result.success(null)
                }
                "openSettings" -> {
                    openSettings(bubbles = call.argument<Boolean>("bubbles") != false)
                    result.success(null)
                }
                "openInApp" -> {
                    openInApp(call.string("roomId"))
                    result.success(null)
                }
                "setLocus" -> {
                    setLocus(call.argument("roomId"))
                    result.success(null)
                }
                "saveToDownloads" -> result.success(
                    saveToDownloads(call.string("fileName"), call.string("text")),
                )
                "copySensitive" -> {
                    copySensitive(call.string("text"))
                    result.success(null)
                }
                "placeholderAvatar" -> result.success(
                    placeholderAvatar(call.string("letters"), call.int("background"), call.int("foreground")),
                )
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            Log.w(TAG, "${call.method} failed", e)
            result.error(e.javaClass.simpleName, e.message, null)
        }
    }

    /**
     * Moves the app behind whatever was open before, so a bubble the person
     * just opened from a chat floats over that instead of over the app.
     */
    private fun minimize() {
        mainWindow?.moveTaskToBack(true)
    }

    /** Android's bubble settings for the app, or its notification settings. */
    private fun openSettings(bubbles: Boolean) {
        fun intent(action: String) =
            Intent(action).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
        if (bubbles && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                return start(intent(Settings.ACTION_APP_NOTIFICATION_BUBBLE_SETTINGS))
            } catch (e: ActivityNotFoundException) {
                Log.w(TAG, "No bubble settings, opening the notification settings", e)
            }
        }
        start(intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS))
    }

    /** Opens a bubble's chat in the main window, which closes the bubble. */
    private fun openInApp(roomId: String) {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return
        intent.action = BubbleIntents.ACTION_OPEN_ROOM
        start(intent.putExtra(BubbleIntents.EXTRA_ROOM_ID, roomId))
    }

    private fun start(intent: Intent) {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        (activity ?: context).startActivity(intent)
    }

    /**
     * Tells Android which chat the main window shows, so it hides that
     * chat's bubble meanwhile.
     */
    private fun setLocus(roomId: String?) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        mainWindow?.setLocusContext(roomId?.let { LocusId(it) }, null)
    }

    /**
     * Saves [text] as a file in Downloads and checks that it was written,
     * returning the file's name; null before Android 10, which has no API
     * for it. Unlike a save dialog, nothing is lost if Android closes the
     * app's window meanwhile, which left recovery key files empty.
     */
    private fun saveToDownloads(fileName: String, text: String): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val bytes = text.toByteArray()
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, fileName)
            put(MediaStore.Downloads.MIME_TYPE, "text/plain")
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IOException("Could not create $fileName in Downloads")
        try {
            val output = resolver.openOutputStream(uri, "w")
                ?: throw IOException("Could not open $fileName")
            output.use { it.write(bytes) }
            val written = resolver.openInputStream(uri)?.use { it.readBytes() }
            if (written == null || !written.contentEquals(bytes)) {
                throw IOException("$fileName was not written completely")
            }
            resolver.update(uri, ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }, null, null)
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
        // Android renames the file if the name is taken
        return resolver.query(uri, arrayOf(MediaStore.Downloads.DISPLAY_NAME), null, null, null)
            ?.use { if (it.moveToFirst()) it.getString(0) else null } ?: fileName
    }

    /** Copies [text], marked as sensitive so Android doesn't show it in its copy preview. */
    private fun copySensitive(text: String) {
        val clip = ClipData.newPlainText("", text)
        clip.description.extras = PersistableBundle().apply {
            putBoolean("android.content.extra.IS_SENSITIVE", true)
        }
        context.getSystemService(ClipboardManager::class.java).setPrimaryClip(clip)
    }

    private fun MethodCall.string(key: String): String =
        argument<String>(key) ?: throw IllegalArgumentException("$key is missing")

    private fun MethodCall.int(key: String): Int =
        argument<Number>(key)?.toInt() ?: throw IllegalArgumentException("$key is missing")

    private fun MethodCall.bubble() = Bubble(
        roomId = string("roomId"),
        icon = argument<ByteArray>("icon"),
        autoExpand = argument<Boolean>("autoExpand") ?: false,
        suppressNotification = argument<Boolean>("suppressNotification") ?: false,
        onlyIfBubbled = argument<Boolean>("onlyIfBubbled") ?: false,
    )

    private companion object {
        const val CHANNEL = "chatapp.marbjo.no/bubbles"
        const val TAG = "GruppechatBubbles"
    }
}
