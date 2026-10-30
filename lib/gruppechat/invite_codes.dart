// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'sign_up.dart';

/// Invite codes are Synapse registration tokens, which only server admins
/// can create. The server's Caddyfile opens just these two admin endpoints.
const String _tokensPath = '_synapse/admin/v1/registration_tokens';

/// The body that asks for a code that works [uses] times for [validFor].
Map<String, Object?> inviteCodeRequest({
  required DateTime now,
  int uses = 1,
  Duration validFor = const Duration(days: 7),
}) => {
  'uses_allowed': uses,
  'expiry_time': now.add(validFor).millisecondsSinceEpoch,
};

/// An invite code and when it stops working.
class InviteCode {
  final String code;
  final DateTime? expires;

  const InviteCode({required this.code, this.expires});

  /// Reads Synapse's answer, such as `{"token": "Abc…", "expiry_time": …}`.
  static InviteCode fromJson(Map<String, Object?> json) {
    final token = json['token'];
    if (token is! String || token.isEmpty) {
      throw const FormatException('No invite code in the response');
    }
    final expiry = json['expiry_time'];
    return InviteCode(
      code: token,
      expires: expiry is int
          ? DateTime.fromMillisecondsSinceEpoch(expiry)
          : null,
    );
  }
}

extension GruppechatInviteCodesExtension on Client {
  Map<String, String> get _adminHeaders => {
    'authorization': 'Bearer $accessToken',
    'content-type': 'application/json',
  };

  /// Whether this account is a server admin, and so can create invite codes.
  Future<bool> canCreateInviteCodes() async {
    final homeserver = this.homeserver;
    if (homeserver == null || accessToken == null) return false;
    final response = await httpClient.get(
      homeserver.resolve('$_tokensPath?valid=true'),
      headers: _adminHeaders,
    );
    return response.statusCode == 200;
  }

  Future<InviteCode> createInviteCode({
    int uses = 1,
    Duration validFor = const Duration(days: 7),
  }) async {
    final response = await httpClient.post(
      homeserver!.resolve('$_tokensPath/new'),
      headers: _adminHeaders,
      body: jsonEncode(
        inviteCodeRequest(now: DateTime.now(), uses: uses, validFor: validFor),
      ),
    );
    if (response.statusCode != 200) {
      unexpectedResponse(response, response.bodyBytes);
    }
    return InviteCode.fromJson(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, Object?>,
    );
  }
}

/// Creates an invite code for a friend and offers to share it with a
/// ready-made message. Accounts that aren't server admins are told to ask
/// an admin instead.
Future<void> showGruppechatInviteDialog(BuildContext context) async {
  final l10n = L10n.of(context);
  final client = Matrix.of(context).client;
  final result = await showFutureLoadingDialog(
    context: context,
    future: () async => await client.canCreateInviteCodes()
        ? await client.createInviteCode()
        : null,
  );
  if (!context.mounted || result.isError) return;
  final invite = result.result;
  if (invite == null) {
    await showOkAlertDialog(
      context: context,
      title: l10n.gruppechatInviteFriend,
      message: l10n.gruppechatOnlyAdminsInvite,
      okLabel: l10n.ok,
    );
    return;
  }

  final materialL10n = MaterialLocalizations.of(context);
  final expires = invite.expires;
  final until = expires == null
      ? ''
      : '${materialL10n.formatMediumDate(expires)} '
            '${materialL10n.formatTimeOfDay(TimeOfDay.fromDateTime(expires), alwaysUse24HourFormat: true)}';
  final host = client.homeserver?.host;
  final message = l10n.gruppechatInviteMessage(
    'https://play.google.com/store/apps/details?id=${AppConfig.appId}',
    host == null ? '' : 'https://${displayHost(host)}',
    invite.code,
    until,
  );

  await showAdaptiveDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog.adaptive(
      title: Text(l10n.gruppechatInviteFriend),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SelectableText(
            invite.code,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'RobotoMono',
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.gruppechatInviteCodeValid(until),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: invite.code));
            Navigator.of(dialogContext).pop();
          },
          child: Text(l10n.copy),
        ),
        TextButton(
          onPressed: () async {
            await FluffyShare.share(message, dialogContext);
            if (dialogContext.mounted) Navigator.of(dialogContext).pop();
          },
          child: Text(l10n.share),
        ),
      ],
    ),
  );
}
