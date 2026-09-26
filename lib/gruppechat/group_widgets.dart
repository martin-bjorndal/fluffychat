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
/// channels: one-time setup, roles and the shared background.
class GruppechatSettingsTiles extends StatelessWidget {
  final Room room;

  const GruppechatSettingsTiles({required this.room, super.key});

  @override
  Widget build(BuildContext context) {
    final group = GruppechatGroup.of(room);
    if (group == null) return const SizedBox.shrink();
    final roles = group.state.roles;
    final background = group.state.background;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (group.needsSetup && group.canSetUp)
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Set up group features'),
            subtitle: const Text(
              'Lets members set nicknames and the background, and '
              'moderators manage roles.',
            ),
            onTap: () =>
                showFutureLoadingDialog(context: context, future: group.setUp),
          ),
        ListTile(
          leading: const Icon(Icons.people_outlined),
          title: const Text('Roles'),
          subtitle: Text(
            roles.isEmpty
                ? 'No roles yet'
                : roles.map((role) => '@${role.id}').join(', '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right_outlined),
          onTap: () => showGroupRolesMenu(context: context, group: group),
        ),
        ListTile(
          leading: const Icon(Icons.brush_outlined),
          title: const Text('Group background'),
          subtitle: Text(background == null ? 'None' : background.kind.name),
          trailing: const Icon(Icons.chevron_right_outlined),
          onTap: () => showGroupBackgroundMenu(context: context, group: group),
        ),
      ],
    );
  }
}

enum _RoleAction { rename, delete }

const String _createRoleValue = ':create';

Future<void> showGroupRolesMenu({
  required BuildContext context,
  required GruppechatGroup group,
}) async {
  final state = group.state;
  final roles = state.roles;
  final picked = await showModalActionPopup<String>(
    context: context,
    title: 'Roles',
    message: roles.isEmpty
        ? 'Roles let you notify several people at once with @role.'
        : 'Mention a role with @ and its ID to notify everyone who has it.',
    cancelLabel: L10n.of(context).cancel,
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
          label: 'Create role…',
          value: _createRoleValue,
          icon: const Icon(Icons.add_outlined),
        ),
    ],
  );
  if (picked == null || !context.mounted) return;

  if (picked == _createRoleValue) {
    final name = await showTextInputDialog(
      context: context,
      title: 'New role',
      hintText: 'e.g. Gamers',
      okLabel: 'Create',
      cancelLabel: L10n.of(context).cancel,
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
    cancelLabel: L10n.of(context).cancel,
    actions: [
      AdaptiveModalAction(
        label: 'Rename',
        value: _RoleAction.rename,
        icon: const Icon(Icons.edit_outlined),
      ),
      AdaptiveModalAction(
        label: 'Delete',
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
        title: 'Rename role',
        initialText: role.name,
        okLabel: 'Save',
        cancelLabel: L10n.of(context).cancel,
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
        title: 'Delete @${role.id}?',
        message: 'Everyone loses this role. This cannot be undone.',
        okLabel: 'Delete',
        cancelLabel: L10n.of(context).cancel,
        isDestructive: true,
      );
      if (consent != OkCancelResult.ok || !context.mounted) return;
      await showFutureLoadingDialog(
        context: context,
        future: () => group.deleteRole(role.id),
      );
  }
}

enum _BackgroundAction { preset, image, clear, toggleVisibility }

Future<void> showGroupBackgroundMenu({
  required BuildContext context,
  required GruppechatGroup group,
}) async {
  final client = group.space.client;
  final showing = client.showGroupBackgrounds;
  final picked = await showModalActionPopup<(_BackgroundAction, int)>(
    context: context,
    title: 'Group background',
    message: group.canSetBackground
        ? 'Everyone in the group sees this background.'
        : 'You do not have permission to change the background here.',
    cancelLabel: L10n.of(context).cancel,
    actions: [
      if (group.canSetBackground) ...[
        for (var i = 0; i < groupBackgroundPresets.length; i++)
          AdaptiveModalAction(
            label: groupBackgroundPresets[i].$1,
            value: (_BackgroundAction.preset, i),
            icon: const Icon(Icons.brush_outlined),
          ),
        AdaptiveModalAction(
          label: 'Image from device…',
          value: (_BackgroundAction.image, 0),
          icon: const Icon(Icons.photo_outlined),
        ),
        if (group.state.background != null)
          AdaptiveModalAction(
            label: 'Remove group background',
            value: (_BackgroundAction.clear, 0),
            icon: const Icon(Icons.delete_outlined),
            isDestructive: true,
          ),
      ],
      AdaptiveModalAction(
        label: showing
            ? 'Hide group backgrounds on my devices'
            : 'Show group backgrounds on my devices',
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
        future: () => group.setBackground(preset),
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
          await group.setBackground(
            GroupBackground(
              kind: GroupBackgroundKind.image,
              url: url,
              opacity: 0.6,
            ),
          );
        },
      );
    case _BackgroundAction.clear:
      await showFutureLoadingDialog(
        context: context,
        future: () => group.setBackground(null),
      );
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
  final state = group.state;
  final isMe = group.space.client.userID == user.id;
  if (!isMe && state.isNicknameLocked(user.id)) {
    await showOkCancelAlertDialog(
      context: context,
      title: 'Nickname locked',
      message:
          '${user.calcDisplayname()} has chosen to set their own nickname.',
    );
    return;
  }
  final current = state.nicknameOf(user.id);
  final setBy = current?.setBy;
  final name = await showTextInputDialog(
    context: context,
    title: 'Nickname for ${user.calcDisplayname()}',
    message: setBy == null
        ? 'Everyone in the group sees this name. Leave it empty to remove it.'
        : 'Currently set by '
              '${group.space.unsafeGetUserFromMemoryOrFallback(setBy).calcDisplayname()}. '
              'Leave it empty to remove it.',
    initialText: current?.name,
    okLabel: 'Save',
    cancelLabel: L10n.of(context).cancel,
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
  final state = group.state;
  final roles = state.roles;
  if (roles.isEmpty) {
    await showOkCancelAlertDialog(
      context: context,
      title: 'No roles yet',
      message: 'Create roles from the details page of the group first.',
    );
    return;
  }
  final assigned = state.roleIdsOf(userId);
  final roleId = await showModalActionPopup<String>(
    context: context,
    title: 'Roles',
    message: 'Tap a role to add or remove it.',
    cancelLabel: L10n.of(context).cancel,
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
