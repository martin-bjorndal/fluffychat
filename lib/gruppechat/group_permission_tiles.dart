// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_permissions_settings/permission_list_tile.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'group_state.dart';

/// The group's own permissions (roles, nicknames, background), shown on a
/// channel's permissions page. They are kept in the group's [space] and
/// apply in all its channels, so they can't be set per channel.
class GroupPermissionTiles extends StatelessWidget {
  final Room space;
  final void Function(String key, int current, int? level) onChanged;

  const GroupPermissionTiles({
    required this.space,
    required this.onChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final powerLevels = space.getState(EventTypes.RoomPowerLevels)?.content;
    final events = powerLevels?.tryGetMap<String, Object?>('events');
    // A type missing from the power levels needs the level for any state
    final stateDefault = powerLevels?.tryGet<int>('state_default') ?? 50;
    return Column(
      mainAxisSize: .min,
      children: [
        Divider(color: theme.dividerColor),
        ListTile(
          title: Text(
            l10n.gruppechatWholeGroupPermissions,
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Text(l10n.gruppechatWholeGroupPermissionsDescription),
        ),
        for (final type in groupEventPowerLevels.keys)
          Builder(
            builder: (context) {
              final level = events?.tryGet<int>(type) ?? stateDefault;
              return PermissionsListTile(
                permissionKey: type,
                category: 'events',
                permission: level,
                canEdit: space.canChangePowerLevel,
                onChanged: (newLevel) => onChanged(type, level, newLevel),
              );
            },
          ),
      ],
    );
  }
}
