// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/file_selector.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'group_state.dart';
import 'matrix_group.dart';

/// Draws a shared group background behind the chat.
class GroupBackgroundLayer extends StatelessWidget {
  final GroupBackground background;

  const GroupBackgroundLayer({required this.background, super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final colors = background.colors.map(Color.new).toList();
    final url = background.url;
    final layer = switch (background.kind) {
      GroupBackgroundKind.solid => ColoredBox(
        color: colors.first,
        child: SizedBox(width: size.width, height: size.height),
      ),
      GroupBackgroundKind.gradient => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: colors,
            transform: GradientRotation(background.rotation * math.pi / 180),
          ),
        ),
        child: SizedBox(width: size.width, height: size.height),
      ),
      GroupBackgroundKind.image => MxcImage(
        cacheKey: url.toString(),
        uri: url,
        fit: BoxFit.cover,
        width: size.width,
        height: size.height,
        isThumbnail: false,
        placeholder: (_) => const SizedBox.shrink(),
      ),
      GroupBackgroundKind.none => const SizedBox.shrink(),
    };
    return Opacity(
      opacity: background.opacity,
      child: background.blur > 0
          ? ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: background.blur,
                sigmaY: background.blur,
              ),
              child: layer,
            )
          : layer,
    );
  }
}

/// Group settings shown on the details page of a space or one of its
/// channels: one-time setup, roles, backgrounds and inviting a role.
class GruppechatSettingsTiles extends StatelessWidget {
  final Room room;

  const GruppechatSettingsTiles({required this.room, super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final group = GruppechatGroup.of(room);
    if (group == null) return const SizedBox.shrink();
    final roles = group.state.roles;
    final background = group.state.background;
    final isChannel = group.space.id != room.id;
    final channelBackground = room.gruppechatChannelBackground;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (group.needsSetup && group.canSetUp)
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: Text(l10n.gruppechatSetUpGroupFeatures),
            subtitle: Text(l10n.gruppechatSetUpGroupFeaturesDescription),
            onTap: () =>
                showFutureLoadingDialog(context: context, future: group.setUp),
          ),
        ListTile(
          leading: const Icon(Icons.people_outlined),
          title: Text(l10n.gruppechatRoles),
          subtitle: Text(
            roles.isEmpty
                ? l10n.gruppechatNoRolesYet
                : roles.map((role) => '@${role.id}').join(', '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right_outlined),
          onTap: () => showGroupRolesMenu(context: context, group: group),
        ),
        ListTile(
          leading: const Icon(Icons.brush_outlined),
          title: Text(l10n.gruppechatGroupBackground),
          subtitle: Text(_backgroundLabel(l10n, background)),
          trailing: const Icon(Icons.chevron_right_outlined),
          onTap: () => showGroupBackgroundMenu(context: context, group: group),
        ),
        if (isChannel)
          ListTile(
            leading: const Icon(Icons.format_paint_outlined),
            title: Text(l10n.gruppechatChannelBackground),
            subtitle: Text(
              channelBackground == null
                  ? l10n.gruppechatSameAsGroup
                  : _backgroundLabel(l10n, channelBackground),
            ),
            trailing: const Icon(Icons.chevron_right_outlined),
            onTap: () => showGroupBackgroundMenu(
              context: context,
              group: group,
              channel: room,
            ),
          ),
        if (isChannel && room.canInvite && roles.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.group_add_outlined),
            title: Text(l10n.gruppechatInviteRole),
            subtitle: Text(l10n.gruppechatInviteRoleDescription),
            onTap: () => showInviteRoleMenu(
              context: context,
              group: group,
              channel: room,
            ),
          ),
      ],
    );
  }
}

String _backgroundLabel(L10n l10n, GroupBackground? background) =>
    switch (background?.kind) {
      null || GroupBackgroundKind.none => l10n.gruppechatNoBackground,
      GroupBackgroundKind.solid => l10n.gruppechatBackgroundSolid,
      GroupBackgroundKind.gradient => l10n.gruppechatBackgroundGradient,
      GroupBackgroundKind.image => l10n.gruppechatBackgroundImage,
    };

String _presetLabel(L10n l10n, String name) => switch (name) {
  'Midnight' => l10n.gruppechatPresetMidnight,
  'Forest' => l10n.gruppechatPresetForest,
  'Sand' => l10n.gruppechatPresetSand,
  'Sunset' => l10n.gruppechatPresetSunset,
  'Aurora' => l10n.gruppechatPresetAurora,
  'Fjord' => l10n.gruppechatPresetFjord,
  _ => name,
};

enum _RoleAction { rename, delete }

const String _createRoleValue = ':create';

Future<void> showGroupRolesMenu({
  required BuildContext context,
  required GruppechatGroup group,
}) async {
  final l10n = L10n.of(context);
  final state = group.state;
  final roles = state.roles;
  final picked = await showModalActionPopup<String>(
    context: context,
    title: l10n.gruppechatRoles,
    message: roles.isEmpty
        ? l10n.gruppechatRolesIntro
        : l10n.gruppechatRolesHowToMention,
    cancelLabel: l10n.cancel,
    actions: [
      for (final role in roles)
        AdaptiveModalAction(
          label:
              '@${role.id} · ${role.name} '
              '(${state.membersWithRole(role.id).length})',
          value: role.id,
          icon: const Icon(Icons.people_outlined),
        ),
      if (group.canManageRoles)
        AdaptiveModalAction(
          label: l10n.gruppechatCreateRole,
          value: _createRoleValue,
          icon: const Icon(Icons.add_outlined),
        ),
    ],
  );
  if (picked == null || !context.mounted) return;

  if (picked == _createRoleValue) {
    final name = await showTextInputDialog(
      context: context,
      title: l10n.gruppechatNewRole,
      hintText: l10n.gruppechatRoleNameHint,
      okLabel: l10n.create,
      cancelLabel: l10n.cancel,
      maxLength: 32,
    );
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    await showFutureLoadingDialog(
      context: context,
      future: () => group.createRole(name),
    );
    return;
  }

  final role = state.roleById(picked);
  if (role == null || !group.canManageRoles) return;
  final action = await showModalActionPopup<_RoleAction>(
    context: context,
    title: '@${role.id} · ${role.name}',
    cancelLabel: l10n.cancel,
    actions: [
      AdaptiveModalAction(
        label: l10n.gruppechatRename,
        value: _RoleAction.rename,
        icon: const Icon(Icons.edit_outlined),
      ),
      AdaptiveModalAction(
        label: l10n.delete,
        value: _RoleAction.delete,
        icon: const Icon(Icons.delete_outlined),
        isDestructive: true,
      ),
    ],
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case _RoleAction.rename:
      final name = await showTextInputDialog(
        context: context,
        title: l10n.gruppechatRenameRole,
        initialText: role.name,
        okLabel: l10n.save,
        cancelLabel: l10n.cancel,
        maxLength: 32,
      );
      if (name == null || name.trim().isEmpty || !context.mounted) return;
      await showFutureLoadingDialog(
        context: context,
        future: () => group.renameRole(role, name),
      );
    case _RoleAction.delete:
      final consent = await showOkCancelAlertDialog(
        context: context,
        title: l10n.gruppechatDeleteRole(role.id),
        message: l10n.gruppechatDeleteRoleWarning,
        okLabel: l10n.delete,
        cancelLabel: l10n.cancel,
        isDestructive: true,
      );
      if (consent != OkCancelResult.ok || !context.mounted) return;
      await showFutureLoadingDialog(
        context: context,
        future: () => group.deleteRole(role.id),
      );
  }
}

/// Invites everyone with a chosen role to [channel].
Future<void> showInviteRoleMenu({
  required BuildContext context,
  required GruppechatGroup group,
  required Room channel,
}) async {
  final l10n = L10n.of(context);
  final state = group.state;
  final roleId = await showModalActionPopup<String>(
    context: context,
    title: l10n.gruppechatInviteRole,
    message: l10n.gruppechatInviteRoleDescription,
    cancelLabel: l10n.cancel,
    actions: [
      for (final role in state.roles)
        AdaptiveModalAction(
          label:
              '@${role.id} · ${role.name} '
              '(${state.membersWithRole(role.id).length})',
          value: role.id,
          icon: const Icon(Icons.people_outlined),
        ),
    ],
  );
  if (roleId == null || !context.mounted) return;
  final result = await showFutureLoadingDialog(
    context: context,
    future: () => group.inviteRole(channel, roleId),
  );
  final invited = result.result;
  if (invited == null || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        invited.isEmpty
            ? l10n.gruppechatEveryoneWithRoleIsHere(roleId)
            : l10n.countInvited(invited.length),
      ),
    ),
  );
}

enum _BackgroundAction { preset, image, clear, none, toggleVisibility }

/// "Pictures and files" in a chat's menu: the gallery and file list of the
/// chat's search, as Messenger's media overview.
List<PopupMenuEntry<T>> gruppechatMediaMenuItems<T>(
  BuildContext context,
  Room room,
) => [
  PopupMenuItem<T>(
    onTap: () => context.go(gruppechatMediaLocation(room)),
    child: Row(
      children: [
        const Icon(Icons.photo_library_outlined),
        const SizedBox(width: 12),
        Text(L10n.of(context).gruppechatPicturesAndFiles),
      ],
    ),
  ),
];

/// Where the chat's pictures and files show.
String gruppechatMediaLocation(Room room) =>
    '/rooms/${room.id}/search?tab=gallery';

/// "Channel background" (or "Group background") in a chat's menu.
List<PopupMenuEntry<T>> gruppechatBackgroundMenuItems<T>(
  BuildContext context,
  Room room,
) {
  final group = GruppechatGroup.of(room);
  if (group == null) return const [];
  final isChannel = group.space.id != room.id;
  final l10n = L10n.of(context);
  return [
    PopupMenuItem<T>(
      onTap: () => showGroupBackgroundMenu(
        context: context,
        group: group,
        channel: isChannel ? room : null,
      ),
      child: Row(
        children: [
          const Icon(Icons.format_paint_outlined),
          const SizedBox(width: 12),
          Text(
            isChannel
                ? l10n.gruppechatChannelBackground
                : l10n.gruppechatGroupBackground,
          ),
        ],
      ),
    ),
  ];
}

/// Picks the group's background, or with [channel] that channel's own
/// background, which overrides the group's there.
Future<void> showGroupBackgroundMenu({
  required BuildContext context,
  required GruppechatGroup group,
  Room? channel,
}) async {
  final l10n = L10n.of(context);
  final client = group.space.client;
  final showing = client.showGroupBackgrounds;
  final canSet = channel == null
      ? group.canSetBackground
      : channel.canSetGruppechatChannelBackground ||
            channel.canChangePowerLevel;
  final current = channel == null
      ? group.state.background
      : channel.gruppechatChannelBackground;
  Future<void> set(GroupBackground? background) => channel == null
      ? group.setBackground(background)
      : channel.setGruppechatChannelBackground(background);

  final picked = await showModalActionPopup<(_BackgroundAction, int)>(
    context: context,
    title: channel == null
        ? l10n.gruppechatGroupBackground
        : l10n.gruppechatChannelBackground,
    message: !canSet
        ? l10n.gruppechatNoBackgroundPermission
        : channel == null
        ? l10n.gruppechatBackgroundForEveryone
        : l10n.gruppechatChannelBackgroundForEveryone,
    cancelLabel: l10n.cancel,
    actions: [
      if (canSet) ...[
        for (var i = 0; i < groupBackgroundPresets.length; i++)
          AdaptiveModalAction(
            label: _presetLabel(l10n, groupBackgroundPresets[i].$1),
            value: (_BackgroundAction.preset, i),
            icon: const Icon(Icons.brush_outlined),
          ),
        AdaptiveModalAction(
          label: l10n.gruppechatImageFromDevice,
          value: (_BackgroundAction.image, 0),
          icon: const Icon(Icons.photo_outlined),
        ),
        if (channel != null && current?.kind != GroupBackgroundKind.none)
          AdaptiveModalAction(
            label: l10n.gruppechatNoBackgroundHere,
            value: (_BackgroundAction.none, 0),
            icon: const Icon(Icons.format_color_reset_outlined),
          ),
        if (current != null)
          AdaptiveModalAction(
            label: channel == null
                ? l10n.gruppechatRemoveGroupBackground
                : l10n.gruppechatUseGroupBackground,
            value: (_BackgroundAction.clear, 0),
            icon: const Icon(Icons.delete_outlined),
            isDestructive: channel == null,
          ),
      ],
      AdaptiveModalAction(
        label: showing
            ? l10n.gruppechatHideGroupBackgrounds
            : l10n.gruppechatShowGroupBackgrounds,
        value: (_BackgroundAction.toggleVisibility, 0),
        icon: Icon(
          showing ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        ),
      ),
    ],
  );
  if (picked == null || !context.mounted) return;

  switch (picked.$1) {
    case _BackgroundAction.preset:
      final preset = groupBackgroundPresets[picked.$2].$2;
      await showFutureLoadingDialog(
        context: context,
        future: () => set(preset),
      );
    case _BackgroundAction.image:
      final files = await selectFiles(context, type: FileType.image);
      if (files.isEmpty || !context.mounted) return;
      final file = files.first;
      await showFutureLoadingDialog(
        context: context,
        future: () async {
          final url = await client.uploadContent(
            await file.readAsBytes(),
            filename: file.name,
          );
          await set(
            GroupBackground(
              kind: GroupBackgroundKind.image,
              url: url,
              opacity: 0.6,
            ),
          );
        },
      );
    case _BackgroundAction.none:
      await showFutureLoadingDialog(
        context: context,
        future: () =>
            set(const GroupBackground(kind: GroupBackgroundKind.none)),
      );
    case _BackgroundAction.clear:
      await showFutureLoadingDialog(context: context, future: () => set(null));
    case _BackgroundAction.toggleVisibility:
      await showFutureLoadingDialog(
        context: context,
        future: () => client.setShowGroupBackgrounds(!showing),
      );
  }
}

/// Lets anyone in the group set or clear [user]'s group-wide nickname.
Future<void> showGroupNicknameDialog({
  required BuildContext context,
  required GruppechatGroup group,
  required User user,
}) async {
  final l10n = L10n.of(context);
  final state = group.state;
  final isMe = group.space.client.userID == user.id;
  if (!isMe && state.isNicknameLocked(user.id)) {
    await showOkCancelAlertDialog(
      context: context,
      title: l10n.gruppechatNicknameLocked,
      message: l10n.gruppechatNicknameLockedDescription(user.calcDisplayname()),
    );
    return;
  }
  final current = state.nicknameOf(user.id);
  final setBy = current?.setBy;
  final name = await showTextInputDialog(
    context: context,
    title: l10n.gruppechatNicknameFor(user.calcDisplayname()),
    message: setBy == null
        ? l10n.gruppechatNicknameDescription
        : l10n.gruppechatNicknameSetBy(
            group.space
                .unsafeGetUserFromMemoryOrFallback(setBy)
                .calcDisplayname(),
          ),
    initialText: current?.name,
    okLabel: l10n.save,
    cancelLabel: l10n.cancel,
    maxLength: 64,
  );
  if (name == null || !context.mounted) return;
  await showFutureLoadingDialog(
    context: context,
    future: () => group.setNickname(user.id, name),
  );
}

/// Toggles whether other people may rename the current user.
Future<void> toggleOwnNicknameLock({
  required BuildContext context,
  required GruppechatGroup group,
}) async {
  final userId = group.space.client.userID;
  if (userId == null) return;
  final locked = group.state.isNicknameLocked(userId);
  await showFutureLoadingDialog(
    context: context,
    future: () => group.setOwnNicknameLocked(!locked),
  );
}

/// Adds or removes one of the group's roles for [userId].
Future<void> showMemberRolesMenu({
  required BuildContext context,
  required GruppechatGroup group,
  required String userId,
}) async {
  final l10n = L10n.of(context);
  final state = group.state;
  final roles = state.roles;
  if (roles.isEmpty) {
    await showOkCancelAlertDialog(
      context: context,
      title: l10n.gruppechatNoRolesYet,
      message: l10n.gruppechatCreateRolesFirst,
    );
    return;
  }
  final assigned = state.roleIdsOf(userId);
  final roleId = await showModalActionPopup<String>(
    context: context,
    title: l10n.gruppechatRoles,
    message: l10n.gruppechatTapRoleToToggle,
    cancelLabel: l10n.cancel,
    actions: [
      for (final role in roles)
        AdaptiveModalAction(
          label: '@${role.id} · ${role.name}',
          value: role.id,
          icon: Icon(
            assigned.contains(role.id)
                ? Icons.check_circle_outlined
                : Icons.circle_outlined,
          ),
        ),
    ],
  );
  if (roleId == null || !context.mounted) return;
  final updated = {...assigned};
  if (!updated.remove(roleId)) updated.add(roleId);
  await showFutureLoadingDialog(
    context: context,
    future: () => group.setMemberRoles(userId, updated),
  );
}
