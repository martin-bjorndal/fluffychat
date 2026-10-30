// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

package chat.fluffy.fluffychat;

import androidx.fragment.app.FragmentActivity;
import io.flutter.embedding.android.FlutterFragment;

/** The Flutter fragment of a {@link SharedEngineActivity}. */
public class SharedEngineFragment extends FlutterFragment {
  private boolean engineTaken = false;
  private boolean windowClosing = false;

  @Override
  public void onDetach() {
    windowClosing = true;
    super.onDetach();
  }

  @Override
  public void detachFromFlutterEngine() {
    engineTaken = true;
    super.detachFromFlutterEngine();
    FragmentActivity activity = getActivity();
    if (activity instanceof SharedEngineActivity) {
      ((SharedEngineActivity) activity).onEngineTaken();
    }
  }

  /**
   * The engine outlives this window: other windows take it over, and
   * MainActivity stops it when the app closes. Flutter would otherwise stop
   * it with the first window that closes, and refuse to let another window
   * take it.
   */
  @Override
  public boolean shouldDestroyEngineWithHost() {
    return false;
  }

  /**
   * Once another window has the engine, that window reports the app's
   * lifecycle. A closing window doesn't report "detached" either: the engine
   * stays for the other windows, so the app is only in the background.
   */
  @Override
  public boolean shouldDispatchAppLifecycleState() {
    return !engineTaken && !windowClosing;
  }
}
