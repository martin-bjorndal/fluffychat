// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:collection/collection.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

import 'group_state.dart';
import 'group_widgets.dart';

/// Draws a [GroupBackgroundKind.pattern] background: the ground colour with
/// the figures repeated over it. Hearts, flowers and stars are icon glyphs
/// from the app's own icon font, so no pictures are needed.
class GroupPatternPainter extends CustomPainter {
  final GroupBackgroundPattern pattern;
  final Color ground;
  final Color figure;

  const GroupPatternPainter({
    required this.pattern,
    required this.ground,
    required this.figure,
  });

  /// Distance between figures, in logical pixels.
  static const double tile = 48;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = ground);
    final paint = Paint()..color = figure;
    final rows = (size.height / tile).ceil() + 1;
    final columns = (size.width / tile).ceil() + 1;
    // Every other row is moved half a tile, as on wallpaper
    final centers = [
      for (var row = 0; row < rows; row++)
        for (var column = 0; column < columns; column++)
          Offset(
            column * tile + (row.isOdd ? tile / 2 : 0),
            row * tile + tile / 2,
          ),
    ];
    final icon = switch (pattern) {
      GroupBackgroundPattern.hearts => Icons.favorite,
      GroupBackgroundPattern.flowers => Icons.local_florist,
      GroupBackgroundPattern.stars => Icons.star,
      _ => null,
    };
    if (icon != null) {
      final glyph = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            fontSize: 22,
            color: figure,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final half = Offset(glyph.width / 2, glyph.height / 2);
      for (final center in centers) {
        glyph.paint(canvas, center - half);
      }
      glyph.dispose();
      return;
    }
    switch (pattern) {
      case GroupBackgroundPattern.dots:
        for (final center in centers) {
          canvas.drawCircle(center, 6, paint);
        }
      case GroupBackgroundPattern.stripes:
        paint.strokeWidth = tile / 4;
        for (var x = -size.height; x < size.width; x += tile / 2) {
          canvas.drawLine(
            Offset(x, size.height),
            Offset(x + size.height, 0),
            paint,
          );
        }
      case GroupBackgroundPattern.checks:
        const half = tile / 2;
        for (var row = 0; row < rows * 2; row++) {
          for (var column = row % 2; column < columns * 2; column += 2) {
            canvas.drawRect(
              Rect.fromLTWH(column * half, row * half, half, half),
              paint,
            );
          }
        }
      default:
    }
  }

  @override
  bool shouldRepaint(GroupPatternPainter oldDelegate) =>
      oldDelegate.pattern != pattern ||
      oldDelegate.ground != ground ||
      oldDelegate.figure != figure;
}

/// The background a person starts from in [showBackgroundColorsDialog]: the
/// current one when it is made of colours, otherwise the first preset.
GroupBackground backgroundToEdit(GroupBackground? current) =>
    switch (current?.kind) {
      GroupBackgroundKind.solid ||
      GroupBackgroundKind.gradient ||
      GroupBackgroundKind.pattern => current!,
      _ => groupBackgroundPresets.first.$2,
    };

/// Lets people pick a ready-made background or make their own of a colour,
/// a gradient or a pattern, with a preview. Returns null when cancelled.
Future<GroupBackground?> showBackgroundColorsDialog({
  required BuildContext context,
  GroupBackground? current,
}) => showDialog<GroupBackground>(
  context: context,
  builder: (_) => _BackgroundColorsDialog(start: backgroundToEdit(current)),
);

class _BackgroundColorsDialog extends StatefulWidget {
  final GroupBackground start;

  const _BackgroundColorsDialog({required this.start});

  @override
  State<_BackgroundColorsDialog> createState() =>
      _BackgroundColorsDialogState();
}

class _BackgroundColorsDialogState extends State<_BackgroundColorsDialog> {
  late GroupBackground _background = widget.start;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final background = _background;
    final content = background.toContent();
    const equals = DeepCollectionEquality();
    final kind = background.kind;
    final colorLabels = switch (kind) {
      GroupBackgroundKind.gradient => [
        l10n.gruppechatColorFrom,
        l10n.gruppechatColorTo,
      ],
      GroupBackgroundKind.pattern => [
        l10n.gruppechatPatternGround,
        l10n.gruppechatPatternFigures,
      ],
      _ => [l10n.gruppechatBackgroundSolid],
    };
    return AlertDialog(
      title: Text(l10n.gruppechatColorsAndPatterns),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Preview(background: background, height: 96),
              const SizedBox(height: 16),
              Text(l10n.gruppechatReadyMade, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (name, preset) in groupBackgroundPresets)
                    Tooltip(
                      message: groupBackgroundPresetLabel(l10n, name),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => setState(() => _background = preset),
                        child: _Preview(
                          background: preset,
                          width: 48,
                          height: 48,
                          selected: equals.equals(preset.toContent(), content),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                l10n.gruppechatMakeYourOwn,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              SegmentedButton<GroupBackgroundKind>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: GroupBackgroundKind.solid,
                    label: Text(l10n.gruppechatBackgroundSolid),
                  ),
                  ButtonSegment(
                    value: GroupBackgroundKind.gradient,
                    label: Text(l10n.gruppechatBackgroundGradient),
                  ),
                  ButtonSegment(
                    value: GroupBackgroundKind.pattern,
                    label: Text(l10n.gruppechatBackgroundPattern),
                  ),
                ],
                selected: {kind},
                onSelectionChanged: (kinds) => setState(
                  () => _background = background.withKind(kinds.single),
                ),
              ),
              if (kind == GroupBackgroundKind.pattern) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final pattern in GroupBackgroundPattern.values)
                      ChoiceChip(
                        label: Text(_patternLabel(l10n, pattern)),
                        selected: background.pattern == pattern,
                        onSelected: (_) => setState(
                          () => _background = background.copyWith(
                            pattern: pattern,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              for (var i = 0; i < colorLabels.length; i++) ...[
                const SizedBox(height: 12),
                Text(colorLabels[i], style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final color in groupBackgroundPalette)
                      _Swatch(
                        color: Color(color),
                        selected: background.colors[i] == color,
                        onTap: () => setState(
                          () => _background = background.withColor(i, color),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(background),
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

String _patternLabel(L10n l10n, GroupBackgroundPattern pattern) =>
    switch (pattern) {
      GroupBackgroundPattern.dots => l10n.gruppechatPatternDots,
      GroupBackgroundPattern.stripes => l10n.gruppechatPatternStripes,
      GroupBackgroundPattern.checks => l10n.gruppechatPatternChecks,
      GroupBackgroundPattern.hearts => l10n.gruppechatPatternHearts,
      GroupBackgroundPattern.flowers => l10n.gruppechatPatternFlowers,
      GroupBackgroundPattern.stars => l10n.gruppechatPatternStars,
    };

Border _selectionBorder(ThemeData theme, bool selected) => Border.all(
  color: selected
      ? theme.colorScheme.primary
      : theme.colorScheme.outlineVariant,
  width: selected ? 3 : 1,
);

class _Preview extends StatelessWidget {
  final GroupBackground background;
  final double? width;
  final double height;
  final bool selected;

  const _Preview({
    required this.background,
    required this.height,
    this.width,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: _selectionBorder(theme, selected),
      ),
      child: GroupBackgroundLayer(background: background),
    );
  }
}

class _Swatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: _selectionBorder(theme, selected),
        ),
      ),
    );
  }
}
