// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:material_ui/material_ui.dart';

import 'matrix_group.dart';
import 'text_replacements.dart';

/// The group settings tile for its text replacements.
class GruppechatTextReplacementsTile extends StatelessWidget {
  final GruppechatGroup group;

  const GruppechatTextReplacementsTile({required this.group, super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final rules = group.textReplacements;
    return ListTile(
      leading: const Icon(Icons.emoji_emotions_outlined),
      title: Text(l10n.gruppechatTextReplacements),
      subtitle: Text(
        rules.isEmpty
            ? l10n.gruppechatNoTextReplacements
            : rules.map((rule) => '$rule').join(', '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right_outlined),
      onTap: () => showTextReplacementsMenu(context: context, group: group),
    );
  }
}

// With a space, so no rule word can be the same
const String _addValue = ' add';
const String _resetValue = ' reset';

/// Lists the group's text replacements. Moderators can add, remove and
/// reset them; everyone else only sees them.
Future<void> showTextReplacementsMenu({
  required BuildContext context,
  required GruppechatGroup group,
}) async {
  final l10n = L10n.of(context);
  final rules = group.textReplacements;
  final canEdit = group.canSetTextReplacements;
  final picked = await showModalActionPopup<String>(
    context: context,
    title: l10n.gruppechatTextReplacements,
    message: l10n.gruppechatTextReplacementsIntro,
    cancelLabel: l10n.cancel,
    actions: [
      for (final rule in rules)
        AdaptiveModalAction(
          label: '$rule',
          value: rule.from,
          icon: Icon(canEdit ? Icons.delete_outlined : Icons.short_text),
        ),
      if (canEdit) ...[
        if (rules.length < maxTextReplacements)
          AdaptiveModalAction(
            label: l10n.gruppechatAddTextReplacement,
            value: _addValue,
            icon: const Icon(Icons.add_outlined),
          ),
        AdaptiveModalAction(
          label: l10n.gruppechatResetTextReplacements,
          value: _resetValue,
          icon: const Icon(Icons.restore_outlined),
        ),
      ],
    ],
  );
  if (picked == null || !canEdit || !context.mounted) return;

  if (picked == _resetValue) {
    await showFutureLoadingDialog(
      context: context,
      future: () => group.setTextReplacements(null),
    );
    return;
  }

  if (picked == _addValue) {
    final from = await showTextInputDialog(
      context: context,
      title: l10n.gruppechatAddTextReplacement,
      labelText: l10n.gruppechatTextReplacementFrom,
      hintText: ':)',
      okLabel: l10n.next,
      cancelLabel: l10n.cancel,
      maxLength: maxTextReplacementFromLength,
      autocorrect: false,
      validator: (text) => TextReplacement(text.trim(), '-').isValid
          ? null
          : l10n.gruppechatTextReplacementOneWord,
    );
    if (from == null || !context.mounted) return;
    final word = from.trim();
    final to = await showTextInputDialog(
      context: context,
      title: word,
      labelText: l10n.gruppechatTextReplacementTo,
      hintText: '🙂',
      okLabel: l10n.save,
      cancelLabel: l10n.cancel,
      maxLength: maxTextReplacementToLength,
      validator: (text) => TextReplacement(word, text.trim()).isValid
          ? null
          : l10n.gruppechatTextReplacementEmpty,
    );
    if (to == null || !context.mounted) return;
    final rule = TextReplacement(word, to.trim());
    if (!rule.isValid) return;
    await showFutureLoadingDialog(
      context: context,
      future: () => group.setTextReplacements(withTextReplacement(rules, rule)),
    );
    return;
  }

  final rule = rules.firstWhere((rule) => rule.from == picked);
  final confirmed = await showOkCancelAlertDialog(
    context: context,
    title: l10n.gruppechatRemoveTextReplacement,
    message: '$rule',
    okLabel: l10n.delete,
    cancelLabel: l10n.cancel,
    isDestructive: true,
  );
  if (confirmed != OkCancelResult.ok || !context.mounted) return;
  await showFutureLoadingDialog(
    context: context,
    future: () => group.setTextReplacements([
      for (final other in rules)
        if (other != rule) other,
    ]),
  );
}
