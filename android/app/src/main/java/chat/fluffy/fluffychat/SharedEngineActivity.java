// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

package chat.fluffy.fluffychat;

import android.content.Context;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.RequiresApi;
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode;
import io.flutter.embedding.android.FlutterFragment;
import io.flutter.embedding.android.FlutterFragmentActivity;
import io.flutter.embedding.android.RenderMode;
import io.flutter.embedding.android.TransparencyMode;
import io.flutter.embedding.engine.FlutterEngine;
import no.marbjo.chatapp.bubbles.BubbleWindow;

/**
 * A window of the app: the main window ({@link MainActivity}) or a chat
 * bubble ({@link BubbleActivity}). All windows show the app's one Flutter
 * engine, so there is one Matrix client, but an engine shows in one window
 * at a time. A window that gets the engine takes it from the window that had
 * it, which stays empty until the person comes back to it. Then it takes the
 * engine back by recreating itself.
 */
public abstract class SharedEngineActivity extends FlutterFragmentActivity implements BubbleWindow {
  /** Windows that exist, shown or not. */
  static int openWindows = 0;

  /** Whether a bubble was the last window to get the engine. */
  static boolean bubbleHadEngine = false;

  private static final long TAKE_BACK_DELAY_MS = 750;

  private final Handler handler = new Handler(Looper.getMainLooper());
  private boolean engineTaken = false;
  private boolean takingBack = false;
  private boolean topResumed = false;

  @Override
  protected void onCreate(@Nullable Bundle savedInstanceState) {
    openWindows++;
    super.onCreate(savedInstanceState);
  }

  @Override
  protected void onDestroy() {
    openWindows--;
    handler.removeCallbacksAndMessages(null);
    super.onDestroy();
  }

  @Override
  public FlutterEngine provideFlutterEngine(@NonNull Context context) {
    return MainActivity.provideEngine(context);
  }

  @Override
  public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
    // Plugins were registered when provideEngine created the engine
    bubbleHadEngine = getBubbleRoomId() != null;
  }

  /**
   * As FlutterFragmentActivity creates its fragment for an engine from
   * provideFlutterEngine(), but with a fragment that shares the engine.
   */
  @NonNull
  @Override
  protected FlutterFragment createFlutterFragment() {
    final BackgroundMode backgroundMode = getBackgroundMode();
    final RenderMode renderMode = getRenderMode();
    return new FlutterFragment.NewEngineFragmentBuilder(SharedEngineFragment.class)
        .dartEntrypoint(getDartEntrypointFunctionName())
        .dartLibraryUri(getDartEntrypointLibraryUri())
        .dartEntrypointArgs(getDartEntrypointArgs())
        .initialRoute(getInitialRoute())
        .appBundlePath(getAppBundlePath())
        .handleDeeplinking(shouldHandleDeeplinking())
        .renderMode(renderMode)
        .transparencyMode(
            backgroundMode == BackgroundMode.opaque
                ? TransparencyMode.opaque
                : TransparencyMode.transparent)
        .shouldAttachEngineToActivity(shouldAttachEngineToActivity())
        .shouldDelayFirstAndroidViewDraw(renderMode == RenderMode.surface)
        .shouldAutomaticallyHandleOnBackPressed(true)
        .build();
  }

  /** Called by {@link SharedEngineFragment} when another window takes the engine. */
  void onEngineTaken() {
    engineTaken = true;
    // The engine belongs in the window the person looks at. Should a window
    // that isn't shown take it while this one stays in front, take it back.
    if (topResumed) {
      handler.postDelayed(
          () -> {
            if (topResumed && hasWindowFocus()) takeEngineBack();
          },
          TAKE_BACK_DELAY_MS);
    }
  }

  /** Whether this window shows the engine, rather than having lost it to another window. */
  boolean hasEngine() {
    return !engineTaken;
  }

  @Override
  protected void onStart() {
    super.onStart();
    takeEngineBack();
  }

  @RequiresApi(Build.VERSION_CODES.Q)
  @Override
  public void onTopResumedActivityChanged(boolean isTopResumedActivity) {
    super.onTopResumedActivityChanged(isTopResumedActivity);
    topResumed = isTopResumedActivity;
    if (isTopResumedActivity) takeEngineBack();
  }

  @Override
  public void onWindowFocusChanged(boolean hasFocus) {
    super.onWindowFocusChanged(hasFocus);
    if (hasFocus) takeEngineBack();
  }

  private void takeEngineBack() {
    if (!engineTaken || takingBack || isFinishing() || isDestroyed()) return;
    takingBack = true;
    // The new instance attaches the engine as it is created
    recreate();
  }
}
