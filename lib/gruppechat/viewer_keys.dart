// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Left and right arrow keys page through the photos of the image viewer
/// on a computer, also after a button in it has been clicked: the keys
/// come up here from whatever has focus inside [child].
class GruppechatArrowKeys extends StatelessWidget {
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final Widget child;

  const GruppechatArrowKeys({
    required this.onPrevious,
    required this.onNext,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: (node, event) {
      // One step per press: not again on release
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      switch (event.logicalKey) {
        case LogicalKeyboardKey.arrowLeft:
          onPrevious();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowRight:
          onNext();
          return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: child,
  );
}
