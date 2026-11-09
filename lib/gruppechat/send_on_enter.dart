// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Lets Enter on a keyboard press "Send" in [child], such as the dialog for a
/// picture pasted into the chat on a computer. Enter counts while nothing in
/// the dialog, one of its text fields or the dialog as a whole has the focus
/// (as after clicking beside the message field), but not on a focused button
/// or switch, where Enter presses that. Shift+Enter doesn't send. [onSend]
/// itself must ignore a second press while it sends.
class GruppechatSendOnEnter extends StatefulWidget {
  final VoidCallback onSend;
  final Widget child;

  /// The "send with Enter" setting, on by default on computers.
  final bool enabled;

  const GruppechatSendOnEnter({
    required this.onSend,
    required this.child,
    this.enabled = true,
    super.key,
  });

  @override
  State<GruppechatSendOnEnter> createState() => _GruppechatSendOnEnterState();
}

class _GruppechatSendOnEnterState extends State<GruppechatSendOnEnter> {
  final FocusNode _node = FocusNode(debugLabel: 'GruppechatSendOnEnter');

  @override
  void initState() {
    super.initState();
    // Seen before the focused widget, so it also works when the focus is on
    // the dialog's route rather than inside this widget
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    _node.dispose();
    super.dispose();
  }

  bool _onKeyEvent(KeyEvent event) {
    if (!widget.enabled || event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return false;
    }
    if (HardwareKeyboard.instance.isShiftPressed) return false;
    if (!mounted || ModalRoute.of(context)?.isCurrent == false) return false;
    final focused = FocusManager.instance.primaryFocus;
    final sends =
        focused == null ||
        focused == _node ||
        focused is FocusScopeNode ||
        focused.context?.findAncestorWidgetOfExactType<EditableText>() != null;
    if (sends) widget.onSend();
    return sends;
  }

  @override
  Widget build(BuildContext context) =>
      Focus(focusNode: _node, autofocus: true, child: widget.child);
}
