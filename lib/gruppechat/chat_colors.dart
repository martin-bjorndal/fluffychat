// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// A chat's own colour: its top bar, input bar and your own bubbles take it,
// and other people's bubbles a tint of it, for everyone in the chat, while
// the background stays as it is. The colour is kept with the chat's
// background (see GruppechatGroup.setChatColor).

import 'dart:async';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'background_picker.dart';
import 'change_notices.dart';
import 'group_state.dart';
import 'matrix_group.dart';

/// Colours offered for a chat.
const List<int> chatColorChoices = [
  0xFFE91E63,
  0xFFF06292,
  0xFFFF6B6B,
  0xFFFF9800,
  0xFFFFD54F,
  0xFF81C784,
  0xFF2E7D32,
  0xFF00897B,
  0xFF4DD0E1,
  0xFF1E88E5,
  0xFF673AB7,
  0xFF9575CD,
  0xFF795548,
  0xFF9E9E9E,
];

/// The colours of a coloured chat's top and bottom bars, and of other
/// people's bubbles in it.
@immutable
class GruppechatChatColors extends ThemeExtension<GruppechatChatColors> {
  final Color bar;
  final Color onBar;
  final Color othersBubble;

  const GruppechatChatColors({
    required this.bar,
    required this.onBar,
    required this.othersBubble,
  });

  @override
  GruppechatChatColors copyWith({
    Color? bar,
    Color? onBar,
    Color? othersBubble,
  }) => GruppechatChatColors(
    bar: bar ?? this.bar,
    onBar: onBar ?? this.onBar,
    othersBubble: othersBubble ?? this.othersBubble,
  );

  @override
  GruppechatChatColors lerp(GruppechatChatColors? other, double t) =>
      other == null
      ? this
      : GruppechatChatColors(
          bar: Color.lerp(bar, other.bar, t)!,
          onBar: Color.lerp(onBar, other.onBar, t)!,
          othersBubble: Color.lerp(othersBubble, other.othersBubble, t)!,
        );

  @override
  bool operator ==(Object other) =>
      other is GruppechatChatColors &&
      other.bar == bar &&
      other.onBar == onBar &&
      other.othersBubble == othersBubble;

  @override
  int get hashCode => Object.hash(bar, onBar, othersBubble);
}

/// The colour of other people's bubbles, and of their typing bubble, under
/// [theme]: a tint of the chat's colour in a coloured chat, and grey
/// elsewhere. Their text stays `onSurface`, which reads on both.
Color gruppechatOthersBubbleColor(ThemeData theme) =>
    theme.extension<GruppechatChatColors>()?.othersBubble ??
    theme.colorScheme.surfaceContainerHigh;

/// The app's theme with [seed] as its colour, for a coloured chat: buttons,
/// bubbles and the bars follow the seed, while the background, the canvas,
/// the dividers, the app bar's defaults and Android's navigation bar keep
/// [base]'s colours. In dark mode the bars are a tint of the seed over the
/// surface, so they differ from your own bubbles (`primaryContainer`) and
/// from the bar of an open thread (`secondaryContainer`). Other people's
/// bubbles are a lighter tint of the seed over the grey they have elsewhere.
ThemeData gruppechatChatTheme(
  BuildContext context,
  ThemeData base,
  Color seed,
) {
  final seeded = FluffyThemes.buildTheme(context, base.brightness, seed);
  final scheme = seeded.colorScheme;
  final light = base.brightness == Brightness.light;
  return seeded.copyWith(
    colorScheme: scheme.copyWith(surface: base.colorScheme.surface),
    scaffoldBackgroundColor: base.scaffoldBackgroundColor,
    canvasColor: base.canvasColor,
    dividerColor: base.dividerColor,
    appBarTheme: base.appBarTheme,
    extensions: [
      GruppechatChatColors(
        bar: light
            ? scheme.primaryContainer
            : Color.alphaBlend(
                scheme.primary.withAlpha(56),
                scheme.surfaceContainer,
              ),
        onBar: light ? scheme.onPrimaryContainer : scheme.onSurface,
        othersBubble: Color.alphaBlend(
          scheme.primary.withAlpha(light ? 40 : 48),
          scheme.surfaceContainerHigh,
        ),
      ),
    ],
  );
}

/// Gives [child] [room]'s chat colour, when it has one, and follows changes
/// to it. It listens itself, since the chat page reads its theme before it
/// listens to the room.
class GruppechatChatColorTheme extends StatefulWidget {
  final Room room;
  final Widget child;

  const GruppechatChatColorTheme({
    required this.room,
    required this.child,
    super.key,
  });

  @override
  State<GruppechatChatColorTheme> createState() =>
      _GruppechatChatColorThemeState();
}

class _GruppechatChatColorThemeState extends State<GruppechatChatColorTheme> {
  StreamSubscription? _changes;

  // The last theme made, kept while the colour and the app's theme stay
  (int, ThemeData, ThemeData)? _made;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(GruppechatChatColorTheme oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room != widget.room) _listen();
  }

  /// Rebuilds when this chat's colour changes in the room keeping it, which
  /// is looked up each time, as the group's space may come later.
  void _listen() {
    final room = widget.room;
    _changes?.cancel();
    _changes = room.client.onRoomState.stream
        .where(
          (update) =>
              update.state.type == GruppechatEventTypes.chatColor &&
              update.state.stateKey == room.id &&
              update.roomId == room.gruppechatBackgroundGroup?.space.id,
        )
        .listen((_) {
          if (mounted) setState(() {});
        });
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.room.gruppechatChatColor;
    if (color == null) return widget.child;
    final base = Theme.of(context);
    var made = _made;
    if (made == null || made.$1 != color || !identical(made.$2, base)) {
      made = _made = (
        color,
        base,
        gruppechatChatTheme(context, base, Color(color)),
      );
    }
    return Theme(data: made.$3, child: widget.child);
  }
}

/// Asks for one of [chatColorChoices], with [current] marked. The answer is a
/// record, so that "none" ((null,), from the button [noneLabel], when given)
/// differs from cancelling (null). Without [canPick] the colours only show.
Future<(int?,)?> showColorChoiceDialog(
  BuildContext context, {
  required String title,
  required String description,
  required int? current,
  bool canPick = true,
  String? noneLabel,
}) => showDialog<(int?,)>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(title),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(description),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final color in chatColorChoices)
                GroupColorSwatch(
                  color: Color(color),
                  selected: current == color,
                  onTap: canPick
                      ? () => Navigator.of(context).pop((color,))
                      : null,
                ),
            ],
          ),
        ],
      ),
    ),
    actions: [
      if (noneLabel != null)
        TextButton(
          onPressed: () => Navigator.of(context).pop((null,)),
          child: Text(noneLabel),
        ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(L10n.of(context).cancel),
      ),
    ],
  ),
);

/// Lets someone pick [room]'s colour for everyone in it, or go back to the
/// app's own.
Future<void> showChatColorDialog(BuildContext context, Room room) async {
  final group = room.gruppechatBackgroundGroup;
  if (group == null) return;
  final l10n = L10n.of(context);
  final current = room.gruppechatChatColor;
  final canSet = group.canSetChatColor;
  final picked = await showColorChoiceDialog(
    context,
    title: l10n.gruppechatChatColor,
    description: canSet
        ? l10n.gruppechatChatColorDescription
        : l10n.gruppechatNoChatColorPermission,
    current: current,
    canPick: canSet,
    noneLabel: canSet && current != null
        ? l10n.gruppechatChatColorDefault
        : null,
  );
  // Someone else may have changed it while the dialog was open
  if (picked == null || picked.$1 == room.gruppechatChatColor) return;
  if (!context.mounted) return;
  await showFutureLoadingDialog(
    context: context,
    future: () => changeChatColor(group, room, picked.$1),
  );
}
