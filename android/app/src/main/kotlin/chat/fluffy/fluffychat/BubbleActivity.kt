// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

package chat.fluffy.fluffychat

import android.os.Bundle
import no.marbjo.chatapp.bubbles.BubbleIntents

/**
 * A chat bubble (Android 11+): one room, floating over other apps. The
 * bubbles plugin posts the notifications whose bubbles open this activity,
 * and it shows the app's shared Flutter engine (see [SharedEngineActivity]).
 */
class BubbleActivity : SharedEngineActivity() {
    private var roomId: String? = null

    override val bubbleRoomId: String? get() = roomId
    override val restoreRoute: Boolean get() = true

    override fun onCreate(savedInstanceState: Bundle?) {
        roomId = savedInstanceState?.getString(STATE_ROOM_ID) ?: BubbleIntents.roomId(intent)
        super.onCreate(savedInstanceState)
        if (roomId == null) finish()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putString(STATE_ROOM_ID, roomId)
    }

    // If the app wasn't running, it starts on the bubble's chat
    override fun getInitialRoute(): String? = roomId?.let { "/rooms/$it" }

    private companion object {
        const val STATE_ROOM_ID = "chatapp.marbjo.no.bubble_room"
    }
}
