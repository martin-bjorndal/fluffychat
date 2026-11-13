// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Whether a dialog's message field takes the focus as the dialog opens, so
/// people can type at once after pasting a picture: where Enter sends, and
/// not in the phone app, as with the chat's own input bar. Otherwise the
/// [GruppechatSendOnEnter] around the dialog takes it.
bool gruppechatFocusMessageField({
  required bool sendOnEnter,
  required bool hasField,
}) => sendOnEnter && hasField && !PlatformInfos.isMobile;

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

  /// Whether the dialog as a whole takes the focus as it opens. Off when a
  /// text field in [child] takes it instead, so people can type at once.
  final bool autofocus;

  const GruppechatSendOnEnter({
    required this.onSend,
    required this.child,
    this.enabled = true,
    this.autofocus = true,
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
      Focus(focusNode: _node, autofocus: widget.autofocus, child: widget.child);
}
