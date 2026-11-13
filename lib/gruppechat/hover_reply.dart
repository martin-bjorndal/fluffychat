// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

/// The [Container] around a message bubble in the chat, with a small reply
/// button beside the bubble while the mouse is over it. It stands in for
/// that container in message.dart, so the hook there stays small.
///
/// The button sits on the side facing the middle of the chat: left of the
/// user's own messages, right of other people's. Touch screens have no
/// hover, so on a phone the message is swiped, or tapped for the reply
/// button at the bottom, as before.
class HoverReplyContainer extends StatefulWidget {
  final bool ownMessage;

  /// Whether the button may show; see `Event.repliesOnHover`.
  final bool enabled;
  final VoidCallback onReply;
  final AlignmentGeometry? alignment;
  final EdgeInsetsGeometry? padding;
  final Widget child;

  const HoverReplyContainer({
    required this.ownMessage,
    required this.enabled,
    required this.onReply,
    this.alignment,
    this.padding,
    required this.child,
    super.key,
  });

  @override
  State<HoverReplyContainer> createState() => _HoverReplyContainerState();
}

class _HoverReplyContainerState extends State<HoverReplyContainer> {
  final _mouseTracker = RendererBinding.instance.mouseTracker;

  // A mouse plugged in or out changes whether the button keeps its room
  void _mouseConnectionChanged() => setState(() {});

  @override
  void initState() {
    super.initState();
    _mouseTracker.addListener(_mouseConnectionChanged);
  }

  @override
  void dispose() {
    _mouseTracker.removeListener(_mouseConnectionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // With a mouse, every message keeps room for the button, so a bubble
    // doesn't move or wrap differently when the mouse comes over it or when
    // it can be replied to. The phone apps keep none: a stylus held over
    // the screen counts as a mouse there.
    final reserveRoom =
        _mouseTracker.mouseIsConnected && !PlatformInfos.isMobile;
    Widget button(bool hovering) => Visibility(
      visible: hovering && widget.enabled,
      maintainState: reserveRoom,
      maintainAnimation: reserveRoom,
      maintainSize: reserveRoom,
      child: IconButton(
        iconSize: 18,
        // Small enough not to make a one-line bubble's row taller
        style: IconButton.styleFrom(
          minimumSize: const Size.square(28),
          fixedSize: const Size.square(28),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        tooltip: L10n.of(context).reply,
        icon: const Icon(Icons.reply_outlined),
        onPressed: widget.onReply,
      ),
    );
    // The tree keeps its shape whatever the button does, so the bubble's
    // own state (a playing video, its animations) is never rebuilt
    return Container(
      alignment: widget.alignment,
      padding: widget.padding,
      child: HoverBuilder(
        builder: (context, hovering) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.ownMessage) button(hovering),
            Flexible(child: widget.child),
            if (!widget.ownMessage) button(hovering),
          ],
        ),
      ),
    );
  }
}
