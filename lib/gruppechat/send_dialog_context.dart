// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/widgets.dart';

/// The context a dialog opened from the chat asks its questions and shows
/// its progress from: the chat's [outerContext] while it is there, else the
/// dialog's own [dialogContext].
///
/// The chat page can be built anew behind an open dialog: when the camera
/// hands a photo back and the phone has turned, the layout changes. Its old
/// context is then gone, and looking up the ScaffoldMessenger from it
/// crashed with "Null check operator used on a null value" (1.1.41).
BuildContext gruppechatLivingContext(
  BuildContext outerContext,
  BuildContext dialogContext,
) => outerContext.mounted ? outerContext : dialogContext;
