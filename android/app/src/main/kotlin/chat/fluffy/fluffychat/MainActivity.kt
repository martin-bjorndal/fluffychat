package chat.fluffy.fluffychat

import io.flutter.embedding.engine.FlutterEngine

import android.content.Context
import android.content.Intent
import android.os.Bundle

class MainActivity : SharedEngineActivity() {

    /** An intent to hand to plugins once this window has the engine. */
    private var heldIntent: Intent? = null
    private var restoreRouteOnAttach = true

    override val bubbleRoomId: String? get() = null
    override val restoreRoute: Boolean get() = restoreRouteOnAttach

    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(base)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Decided before super.onCreate(), where this window gets the engine:
        // after a bubble, the app goes back to where it was, unless this
        // window was opened for something (a notification tap, a shared file)
        val held = intentWhileAway.also { intentWhileAway = null }
            ?: intent.takeIf { savedInstanceState == null && bubbleHadEngine }
        restoreRouteOnAttach = held == null || held.action == Intent.ACTION_MAIN
        heldIntent = held?.takeUnless { it.action == Intent.ACTION_MAIN }
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        // While a bubble has the engine, nobody hears about this intent: keep
        // it for when this window takes the engine back
        if (!hasEngine()) intentWhileAway = intent
        super.onNewIntent(intent)
    }

    override fun onPostResume() {
        super.onPostResume()
        val held = heldIntent ?: return
        heldIntent = null
        onNewIntent(held)
    }

    override fun onDestroy() {
        val closing = isFinishing && hasEngine() && openWindows == 1
        super.onDestroy()
        // The app closed, so its engine stops too, unless a bubble still
        // needs it
        if (closing) engine?.destroy()
    }

    companion object {
        var engine: FlutterEngine? = null
        private var intentWhileAway: Intent? = null

        @JvmStatic
        fun provideEngine(context: Context): FlutterEngine {
            val eng = engine ?: FlutterEngine(context.applicationContext, emptyArray(), true, false).also {
                it.addEngineLifecycleListener(object : FlutterEngine.EngineLifecycleListener {
                    override fun onPreEngineRestart() {}

                    override fun onEngineWillDestroy() {
                        if (engine === it) engine = null
                    }
                })
            }
            engine = eng
            return eng
        }
    }
}
