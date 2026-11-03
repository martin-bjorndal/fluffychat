// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:file_picker/file_picker.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter/services.dart';
import 'package:gruppechat_bubbles/gruppechat_bubbles.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

const _channel = MethodChannel(gruppechatBubblesChannel);

/// A file name for the recovery key, without characters such as ":" that
/// some file systems refuse.
String recoveryKeyFileName(DateTime time) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'Hanne-Chat-Recovery-Key-${time.year}-${two(time.month)}-'
      '${two(time.day)}-${two(time.hour)}${two(time.minute)}.txt';
}

/// Saves the recovery key as a file and returns whether it was saved.
///
/// On Android 10 and newer it goes straight to Downloads and is checked
/// after writing. Android's save dialog, which the file picker uses, left
/// the file empty when Android closed the app's window while the dialog was
/// open, since the picker only kept the key in memory.
Future<bool> saveRecoveryKeyFile(BuildContext context, String key) async {
  final l10n = L10n.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final fileName = recoveryKeyFileName(DateTime.now());
  try {
    if (PlatformInfos.isAndroid) {
      final saved = await _channel.invokeMethod<String>('saveToDownloads', {
        'fileName': fileName,
        'text': key,
      });
      if (saved != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.gruppechatRecoveryKeySaved(saved)),
            showCloseIcon: true,
          ),
        );
        return true;
      }
    }
    final path = await FilePicker.saveFile(
      fileName: fileName,
      bytes: Uint8List.fromList(key.codeUnits),
    );
    return path != null;
  } catch (e, s) {
    Logs().w('Could not save the recovery key', e, s);
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.gruppechatRecoveryKeyNotSaved(e.toString())),
        showCloseIcon: true,
      ),
    );
    return false;
  }
}

/// Copies the recovery key, to paste into a password manager. On Android
/// it is marked as sensitive, so the copy preview doesn't show it.
Future<void> copyRecoveryKey(BuildContext context, String key) async {
  final l10n = L10n.of(context);
  final messenger = ScaffoldMessenger.of(context);
  if (PlatformInfos.isAndroid) {
    try {
      await _channel.invokeMethod('copySensitive', {'text': key});
    } catch (e, s) {
      Logs().w('Could not copy as sensitive', e, s);
      await Clipboard.setData(ClipboardData(text: key));
    }
  } else if (context.mounted) {
    await FluffyShare.share(key, context, copyOnly: true);
  }
  messenger.showSnackBar(
    SnackBar(
      content: Text(l10n.gruppechatRecoveryKeyCopied),
      showCloseIcon: true,
    ),
  );
}
