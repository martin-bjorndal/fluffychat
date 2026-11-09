// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// "Open gallery" as its own button next to the + in the chat's input bar,
/// so pictures and videos are one tap away instead of inside the + menu.
/// Like the +, it makes room for the text while people write ([hidden]).
class GruppechatGalleryButton extends StatelessWidget {
  final bool hidden;
  final double height;
  final VoidCallback onPressed;

  const GruppechatGalleryButton({
    required this.hidden,
    required this.height,
    required this.onPressed,
    super.key,
  });

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: FluffyThemes.animationDuration,
    curve: FluffyThemes.animationCurve,
    width: hidden ? 0 : 40,
    height: height,
    alignment: Alignment.center,
    decoration: const BoxDecoration(),
    clipBehavior: Clip.hardEdge,
    child: IconButton(
      tooltip: L10n.of(context).openGallery,
      color: Theme.of(context).colorScheme.onPrimaryContainer,
      icon: const Icon(Icons.photo_library_outlined),
      onPressed: hidden ? null : onPressed,
    ),
  );
}
