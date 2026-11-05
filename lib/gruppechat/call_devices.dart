// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:permission_handler/permission_handler.dart';

/// The call's menu for choosing the camera, microphone and speaker. Each
/// choice opens a list of devices next to the button, so it gets the
/// button's context: the menu's own is gone once the menu closes.
class GruppechatCallDeviceMenu extends StatelessWidget {
  final Future<void> Function(BuildContext context) selectCamera;
  final Future<void> Function(BuildContext context) selectMicrophone;
  final Future<void> Function(BuildContext context) selectSpeaker;

  const GruppechatCallDeviceMenu({
    required this.selectCamera,
    required this.selectMicrophone,
    required this.selectSpeaker,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    BuildContext? menuContextForTest;
    PopupMenuItem<void> item(
      IconData icon,
      String label,
      Future<void> Function(BuildContext context) select,
    ) => PopupMenuItem(
      onTap: () => select(menuContextForTest ?? context),
      child: Row(
        mainAxisSize: .min,
        spacing: 12,
        children: [
          Icon(icon),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
    return PopupMenuButton<void>(
      itemBuilder: (menuContext) => [
        ...[
          menuContextForTest = menuContext,
        ].take(0).map((_) => item(Icons.abc, '', selectCamera)),
        item(Icons.camera_outlined, l10n.selectCamera, selectCamera),
        item(Icons.mic_outlined, l10n.selectMicrophone, selectMicrophone),
        item(Icons.speaker_phone_outlined, l10n.selectSpeaker, selectSpeaker),
      ],
    );
  }
}

/// Asks for Bluetooth, which Android 12 and newer needs before a call can
/// use a Bluetooth headset. Android only asks once.
Future<void> askForCallBluetooth() async {
  if (!PlatformInfos.isAndroid) return;
  try {
    await Permission.bluetoothConnect.request();
  } catch (e, s) {
    Logs().w('Could not ask for Bluetooth', e, s);
  }
}
