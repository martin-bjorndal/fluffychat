// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

package no.marbjo.chatapp.bubbles

import android.content.Intent
import android.net.Uri

/**
 * Implemented by the app's activities that show the Flutter UI, so the
 * plugin can tell Dart what the window that just got the engine shows.
 */
interface BubbleWindow {
    /** The room this window shows as a bubble, or null for the main window. */
    val bubbleRoomId: String?

    /**
     * Whether the app should go back to where it was before a bubble took
     * over. False when the main window was opened for something specific,
     * such as a tapped notification, which then decides where to go.
     */
    val restoreRoute: Boolean
}

/** The intents that open chats from bubbles and into bubbles. */
object BubbleIntents {
    /** Opens a room in a bubble. The app's bubble activity has an intent filter for it. */
    const val ACTION_BUBBLE = "chatapp.marbjo.no.action.BUBBLE"

    /** Opens a room in the main window, from its bubble. */
    const val ACTION_OPEN_ROOM = "chatapp.marbjo.no.action.OPEN_ROOM"

    const val EXTRA_ROOM_ID = "roomId"

    private const val SCHEME = "gruppechat"
    private const val HOST = "bubble"

    /** Gives each room's bubble its own intent. */
    internal fun uri(roomId: String): Uri =
        Uri.Builder().scheme(SCHEME).authority(HOST).appendPath(roomId).build()

    /** The room a bubble's intent opens. */
    fun roomId(intent: Intent?): String? =
        intent?.data?.takeIf { it.scheme == SCHEME && it.host == HOST }?.lastPathSegment
}
