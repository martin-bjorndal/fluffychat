// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:file_picker/file_picker.dart';
import 'package:fluffychat/gruppechat/web_files.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/app_lock.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';

Future<List<XFile>> selectFiles(
  BuildContext context, {
  String? title,
  FileType type = FileType.any,
  bool allowMultiple = false,
}) async {
  final result = await AppLock.of(context).pauseWhile(
    showFutureLoadingDialog(
      context: context,
      future: () async {
        // Gruppechat: on phones, pictures and videos come from the gallery
        // (Android's photo picker) instead of the file browser
        if (PlatformInfos.isMobile) {
          final picker = ImagePicker();
          switch (type) {
            case FileType.media:
              return allowMultiple
                  ? await picker.pickMultipleMedia()
                  : [?await picker.pickMedia()];
            case FileType.image:
              return allowMultiple
                  ? await picker.pickMultiImage()
                  : [?await picker.pickImage(source: ImageSource.gallery)];
            case FileType.video:
              return [?await picker.pickVideo(source: ImageSource.gallery)];
            default:
          }
        }
        // Gruppechat: in the browser, a picker that Safari on iPhone doesn't
        // leave hanging (lib/gruppechat/web_files.dart)
        final webFiles = await pickWebFiles(
          type: type,
          allowMultiple: allowMultiple,
        );
        if (webFiles != null) return webFiles;
        if (allowMultiple) {
          final result = await FilePicker.pickFiles(
            type: type,
            dialogTitle: title,
          );
          return result.map((file) => file.xFile).toList();
        }
        final result = await FilePicker.pickFile(
          type: type,
          dialogTitle: title,
        );
        return [?result?.xFile];
      },
    ),
  );
  return result.result ?? [];
}
