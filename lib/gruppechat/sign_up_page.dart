// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/layouts/login_scaffold.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'sign_up.dart';

/// Creates an account on a server that hands out invite codes. Opened by
/// "Create new account" when the server has no sign-up website of its own.
class GruppechatSignUpPage extends StatefulWidget {
  final Client client;

  const GruppechatSignUpPage({required this.client, super.key});

  @override
  State<GruppechatSignUpPage> createState() => _GruppechatSignUpPageState();
}

class _GruppechatSignUpPageState extends State<GruppechatSignUpPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _inviteCodeController = TextEditingController();
  String? _usernameError, _passwordError, _inviteCodeError, _error;
  bool _loading = false;
  bool _showPassword = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _inviteCodeController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    final username = normalizeUsername(_usernameController.text);
    final password = _passwordController.text;
    final inviteCode = _inviteCodeController.text.trim();
    setState(() {
      _usernameError = username.isEmpty ? 'Choose a username' : null;
      _passwordError = password.length < 8 ? 'Use at least 8 characters' : null;
      _inviteCodeError = inviteCode.isEmpty
          ? 'Enter the invite code you were given'
          : null;
      _error = null;
    });
    if (_usernameError != null ||
        _passwordError != null ||
        _inviteCodeError != null) {
      return;
    }

    setState(() => _loading = true);
    try {
      await signUpWithInviteCode(
        widget.client,
        username: username,
        password: password,
        inviteCode: inviteCode,
        deviceName: PlatformInfos.appDisplayName,
      );
      if (mounted) context.go('/backup');
      return;
    } on SignUpException catch (e) {
      if (!mounted) return;
      setState(() {
        switch (e.problem) {
          case SignUpProblem.missingInviteCode:
            _inviteCodeError = 'Enter the invite code you were given';
          case SignUpProblem.invalidInviteCode:
            _inviteCodeError = 'This invite code is wrong, used up or expired';
          case SignUpProblem.usernameTaken:
            _usernameError = 'That username is taken';
          case SignUpProblem.invalidUsername:
            _usernameError =
                'Use only lowercase letters, numbers, dots, dashes and '
                'underscores';
          case SignUpProblem.weakPassword:
            _passwordError = e.serverMessage ?? 'Choose a stronger password';
          case SignUpProblem.signUpDisabled:
            _error = 'This server does not accept new accounts right now.';
          case SignUpProblem.unsupported:
            _error =
                'This server does not support signing up with an invite '
                'code.';
          case SignUpProblem.other:
            _error = e.serverMessage ?? 'Something went wrong. Try again.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final homeserver = widget.client.homeserver?.host;
    final error = _error;
    return LoginScaffold(
      appBar: AppBar(
        leading: _loading ? null : const Center(child: BackButton()),
        automaticallyImplyLeading: !_loading,
        titleSpacing: !_loading ? 0 : null,
        title: Text(L10n.of(context).createNewAccount),
      ),
      body: AutofillGroup(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          children: [
            Center(
              child: Hero(
                tag: 'info-logo',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(128),
                  child: Image.asset(
                    './assets/logo/mini/logo_mini.png',
                    width: 128,
                    height: 128,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (homeserver != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Create an account on $homeserver. You need an invite code '
                  'from the group admin.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TextField(
                readOnly: _loading,
                autocorrect: false,
                autofocus: true,
                controller: _usernameController,
                textInputAction: TextInputAction.next,
                autofillHints: _loading
                    ? null
                    : const [AutofillHints.newUsername],
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.account_box_outlined),
                  errorText: _usernameError,
                  hintText: 'e.g. martin',
                  labelText: 'Username',
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TextField(
                readOnly: _loading,
                autocorrect: false,
                controller: _passwordController,
                obscureText: !_showPassword,
                textInputAction: TextInputAction.next,
                autofillHints: _loading
                    ? null
                    : const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.lock_outlined),
                  errorText: _passwordError,
                  labelText: L10n.of(context).password,
                  suffixIcon: IconButton(
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TextField(
                readOnly: _loading,
                autocorrect: false,
                controller: _inviteCodeController,
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => _signUp(),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.vpn_key_outlined),
                  errorText: _inviteCodeError,
                  labelText: 'Invite code',
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                ),
                onPressed: _loading ? null : _signUp,
                child: _loading
                    ? const LinearProgressIndicator()
                    : Text(L10n.of(context).createNewAccount),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  error,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
