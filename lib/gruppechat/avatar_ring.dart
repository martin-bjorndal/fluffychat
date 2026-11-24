// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Wish from 1.1.45 (Karina): a coloured ring around your profile picture,
// which everyone sees. The colour is a custom field in your Matrix profile
// (Synapse serves those without any setting), so nothing is sent to rooms.
// Others read it with the rest of your profile, at most an hour old, as
// custom fields don't come through sync.

import 'dart:async';
import 'dart:math';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'chat_colors.dart';

/// The profile field with the ring's colour, as an ARGB int.
const avatarRingField = 'no.gruppechat.avatar_ring';

/// How old a looked-up ring may be before it is looked up again. Others
/// see a new ring after at most this, when the avatar is next drawn; custom
/// profile fields don't come through sync.
const avatarRingMaxAge = Duration(hours: 1);

/// How long a lookup that failed (no network, say) is kept, rather than
/// hiding the ring for the whole [avatarRingMaxAge].
const avatarRingRetryAfter = Duration(seconds: 30);

/// Bumped when a looked-up ring has changed, so avatars on screen look again.
final avatarRingChanges = ValueNotifier<int>(0);

final _lookups = Expando<Map<String, _Lookup>>();

class _Lookup {
  final DateTime at = DateTime.now();
  final Future<Color?> color;

  /// The colour once looked up, or until then what was known before.
  Color? known;
  bool failed = false;
  _Lookup(this.color, this.known);

  bool get stale =>
      DateTime.now().difference(at) >
      (failed ? avatarRingRetryAfter : avatarRingMaxAge);
}

/// The ring colour of [userId] as last looked up, or null.
Color? knownAvatarRing(Client client, String userId) =>
    _lookups[client]?[userId]?.known;

/// The ring colour [userId] has chosen, or null for none (or when it can't be
/// looked up). Kept in memory, so a screen full of someone's avatars asks the
/// server once; [fresh] asks again at once.
///
/// It reads the one field rather than the whole profile: the SDK can't read
/// a profile whose `avatar_url` isn't an mxc URI.
Future<Color?> avatarRingColor(
  Client client,
  String userId, {
  bool fresh = false,
}) {
  final lookups = _lookups[client] ??= {};
  final before = lookups[userId];
  if (!fresh && before != null && !before.stale) return before.color;
  final completer = Completer<Color?>();
  final lookup = lookups[userId] = _Lookup(completer.future, before?.known);
  _lookUp(client, userId).then((result) {
    final (color, failed) = result;
    final earlier = lookup.known;
    lookup.failed = failed;
    // Without an answer, keep showing what was known
    if (!failed) lookup.known = color;
    completer.complete(lookup.known);
    if (before != null && lookup.known != earlier) avatarRingChanges.value++;
  });
  return lookup.color;
}

/// The colour, and whether the lookup failed without an answer.
Future<(Color?, bool)> _lookUp(Client client, String userId) async {
  try {
    final fields = await client.getProfileField(userId, avatarRingField);
    return (avatarRingFromProfile(fields), false);
  } on MatrixException catch (e) {
    // The server answered: M_NOT_FOUND when they have no ring; anything
    // else (a server without custom fields, say) counts as none too
    if (e.error != MatrixError.M_NOT_FOUND) {
      Logs().d('No avatar ring for $userId', e);
    }
    return (null, false);
  } catch (e) {
    Logs().d('Could not look up the avatar ring of $userId', e);
    return (null, true);
  }
}

/// The ring colour in a profile's [fields], or null when there is none or
/// it isn't one of the colours the app offers.
Color? avatarRingFromProfile(Map<String, Object?> fields) {
  final value = fields[avatarRingField];
  return value is int && chatColorChoices.contains(value) ? Color(value) : null;
}

/// Gives your own picture a ring of [color], or takes it away with null,
/// unless it already has that ring ([current]).
Future<void> changeAvatarRing(
  Client client,
  Color? current,
  Color? color,
) async {
  if (color == current) return;
  final userId = client.userID!;
  if (color == null) {
    await client.deleteProfileField(userId, avatarRingField);
  } else {
    await client.setProfileField(userId, avatarRingField, {
      avatarRingField: color.toARGB32(),
    });
  }
  // Your own avatars change at once
  await avatarRingColor(client, userId, fresh: true);
}

/// [child], an avatar of [size], with [userId]'s ring around it when they
/// have one. The outer size stays [size] either way, so nothing around it
/// moves; with a ring the picture shrinks a little inside it.
class AvatarRing extends StatefulWidget {
  final Client? client;
  final String? userId;
  final double size;
  final Widget child;

  const AvatarRing({
    required this.client,
    required this.userId,
    required this.size,
    required this.child,
    super.key,
  });

  @override
  State<AvatarRing> createState() => _AvatarRingState();
}

class _AvatarRingState extends State<AvatarRing> {
  Future<Color?>? _lookup;
  Client? _client;
  Color? _color;

  @override
  void initState() {
    super.initState();
    avatarRingChanges.addListener(_lookAgain);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The account may have changed when the avatar has no client of its own
    if (_lookup == null || _client != _clientOf()) _lookUp();
  }

  @override
  void didUpdateWidget(AvatarRing old) {
    super.didUpdateWidget(old);
    if (old.userId != widget.userId || old.client != widget.client) {
      _color = null;
      _lookUp();
    }
  }

  @override
  void dispose() {
    avatarRingChanges.removeListener(_lookAgain);
    super.dispose();
  }

  /// A ring was looked up anew and changed: redraw only if it is this one.
  void _lookAgain() {
    final userId = widget.userId;
    if (userId == null || _client == null) return;
    final color = knownAvatarRing(_client!, userId);
    if (color != _color) setState(() => _color = color);
  }

  Client _clientOf() => widget.client ?? Matrix.of(context).client;

  void _lookUp() {
    final userId = widget.userId;
    if (userId == null || !userId.isValidMatrixIdStrict()) {
      _lookup = null;
      _color = null;
      return;
    }
    final client = _client = _clientOf();
    // Known already, so a new avatar shows its ring from the first frame
    _color = knownAvatarRing(client, userId) ?? _color;
    final lookup = _lookup = avatarRingColor(client, userId);
    lookup.then((color) {
      if (mounted && identical(lookup, _lookup) && color != _color) {
        setState(() => _color = color);
      }
    });
  }

  @override
  Widget build(BuildContext context) =>
      gruppechatRingedAvatar(widget.size, _color, widget.child);
}

/// [child] of [size] inside a ring of [color], [size] across in all; just
/// [child] without a [color]. The tree is the same either way, so a ring
/// coming or going doesn't load the picture again.
Widget gruppechatRingedAvatar(double size, Color? color, Widget child) {
  final width = color == null ? 0.0 : max(2.0, size / 16);
  return Container(
    key: color == null ? null : avatarRingKey,
    width: size,
    height: size,
    padding: EdgeInsets.all(width * 1.5),
    decoration: color == null
        ? null
        : BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: width),
          ),
    child: FittedBox(child: child),
  );
}

/// The key of the ring, for tests.
const avatarRingKey = ValueKey('gruppechat-avatar-ring');

/// Lets you pick a ring for your own picture, or take it away.
Future<void> showAvatarRingDialog(BuildContext context, Client client) async {
  final l10n = L10n.of(context);
  final current = await avatarRingColor(client, client.userID!);
  if (!context.mounted) return;
  final picked = await showColorChoiceDialog(
    context,
    title: l10n.gruppechatAvatarRing,
    description: l10n.gruppechatAvatarRingDescription,
    current: current?.toARGB32(),
    noneLabel: l10n.gruppechatAvatarRingNone,
  );
  if (picked == null || !context.mounted) return;
  final color = picked.$1;
  await showFutureLoadingDialog(
    context: context,
    future: () =>
        changeAvatarRing(client, current, color == null ? null : Color(color)),
  );
}

/// The button under your name in the settings that opens
/// [showAvatarRingDialog].
class AvatarRingButton extends StatelessWidget {
  const AvatarRingButton({super.key});

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: () => showAvatarRingDialog(context, Matrix.of(context).client),
    icon: const Icon(Icons.circle_outlined, size: 16),
    label: Text(L10n.of(context).gruppechatAvatarRing),
  );
}
