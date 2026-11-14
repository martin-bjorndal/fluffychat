// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

/// Whether a finished sideways swipe in a chat goes back to the chat list:
/// it went right (towards the start of the page) and either covered a
/// quarter of [width] or ended in a fling, as fast as a message swipe needs
/// (700 px/s, as in swipe_to_action). A drag that barely moved, or was
/// flung back to the left at the end, never counts; nor does one in a
/// widget of unknown width.
bool gruppechatIsSwipeBack({
  required double distance,
  required double velocity,
  required double width,
}) {
  if (width <= 0 || distance < 24) return false;
  if (velocity < -700) return false;
  return distance >= width / 4 || velocity > 700;
}

/// On a phone, swiping right in a chat goes back to the chat list, like the
/// back button, so selecting, the emoji picker and threads keep their back
/// rules (PopScope in pages/chat/chat_view.dart). A swipe that starts on a
/// message ([GruppechatSwipeBack.exempt]) is left to it: there it replies.
/// Only touch and pen count, so the mouse still selects text on a PC, and
/// touches at the screen edges are left to the system's own back swipes.
class GruppechatSwipeBack extends StatefulWidget {
  final bool enabled;
  final VoidCallback onBack;
  final Widget child;

  const GruppechatSwipeBack({
    required this.enabled,
    required this.onBack,
    required this.child,
    super.key,
  });

  /// Marks [child] (a message) as a place where a swipe never goes back.
  static Widget exempt({required Widget child}) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (event) => _exemptPointers.add(event.pointer),
    onPointerUp: (event) => _exemptPointers.remove(event.pointer),
    onPointerCancel: (event) => _exemptPointers.remove(event.pointer),
    child: child,
  );

  /// Pointers that went down on a message. Being deeper, its listener sees
  /// a touch before the swipe's recognizer is asked about it.
  static final Set<int> _exemptPointers = {};

  /// The strip at each side that belongs to the system's back swipe: the
  /// phone's gesture area, and at least iOS's own edge swipe (20 px).
  static const double minEdgeWidth = 20;

  @override
  State<GruppechatSwipeBack> createState() => _GruppechatSwipeBackState();
}

class _GruppechatSwipeBackState extends State<GruppechatSwipeBack> {
  double _distance = 0;

  bool _allows(PointerEvent event) {
    if (!widget.enabled || !mounted) return false;
    if (GruppechatSwipeBack._exemptPointers.contains(event.pointer)) {
      return false;
    }
    // Only what it needs, so the keyboard sliding in doesn't rebuild it
    final insets = MediaQuery.systemGestureInsetsOf(context);
    const edge = GruppechatSwipeBack.minEdgeWidth;
    final x = event.position.dx;
    return x >= max(insets.left, edge) &&
        x <= MediaQuery.sizeOf(context).width - max(insets.right, edge);
  }

  void _start(DragStartDetails details) => _distance = 0;

  void _update(DragUpdateDetails details) => _distance += details.delta.dx;

  void _end(DragEndDetails details) {
    if (gruppechatIsSwipeBack(
      distance: _distance * _sign,
      velocity: details.velocity.pixelsPerSecond.dx * _sign,
      width: context.size?.width ?? 0,
    )) {
      widget.onBack();
    }
  }

  /// Rightward is positive; in a right-to-left layout back is leftward.
  double get _sign =>
      Directionality.of(context) == TextDirection.rtl ? -1.0 : 1.0;

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    behavior: HitTestBehavior.translucent,
    gestures: {
      _SwipeBackRecognizer:
          GestureRecognizerFactoryWithHandlers<_SwipeBackRecognizer>(
            () => _SwipeBackRecognizer(_allows),
            (recognizer) => recognizer
              ..onStart = _start
              ..onUpdate = _update
              ..onEnd = _end,
          ),
    },
    child: widget.child,
  );
}

class _SwipeBackRecognizer extends HorizontalDragGestureRecognizer {
  final bool Function(PointerEvent) allows;

  _SwipeBackRecognizer(this.allows)
    : super(
        supportedDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
          PointerDeviceKind.invertedStylus,
        },
      );

  @override
  bool isPointerAllowed(PointerEvent event) =>
      allows(event) && super.isPointerAllowed(event);
}
