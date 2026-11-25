// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Wish from 1.1.45 (Karina): a coloured ring around your profile picture,
// which everyone sees. The colour is a custom field in your Matrix profile
// (Synapse serves those without any setting), so nothing is sent to rooms.
// Others read it field by field, at most an hour old, as custom fields
// don't come through sync.
//
// Wish from 1.1.46 (Karina): glitter rings and a Christmas ring. The kind
// is a second field; the colour field stays as it was, so a 1.1.45 app
// still shows a plain ring in that colour (red for Christmas).

import 'dart:async';
import 'dart:math';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'background_picker.dart';
import 'chat_colors.dart';
import 'effects.dart';

/// The profile field with the ring's colour, as an ARGB int.
const avatarRingField = 'no.gruppechat.avatar_ring';

/// The profile field with the ring's kind, an [AvatarRingKind.name]; not
/// there for a plain ring.
const avatarRingStyleField = 'no.gruppechat.avatar_ring_style';

/// How old a looked-up ring may be before it is looked up again. Others
/// see a new ring after at most this, when the avatar is next drawn; custom
/// profile fields don't come through sync.
const avatarRingMaxAge = Duration(hours: 1);

/// How long a lookup that failed (no network, say) is kept, rather than
/// hiding the ring for the whole [avatarRingMaxAge].
const avatarRingRetryAfter = Duration(seconds: 30);

/// Bumped when a looked-up ring has changed, so avatars on screen look again.
final avatarRingChanges = ValueNotifier<int>(0);

enum AvatarRingKind { plain, glitter, christmas }

/// How someone's ring looks: its colour and kind.
@immutable
class AvatarRingLook {
  final Color color;
  final AvatarRingKind kind;

  const AvatarRingLook(this.color, [this.kind = AvatarRingKind.plain]);

  /// The Christmas ring. Its colour is what a 1.1.45 app shows, one of
  /// [chatColorChoices] so those apps accept it; when the colour field holds
  /// another, such an app has picked a plain ring since.
  static const christmas = AvatarRingLook(
    Color(0xFFFF6B6B),
    AvatarRingKind.christmas,
  );

  @override
  bool operator ==(Object other) =>
      other is AvatarRingLook && other.color == color && other.kind == kind;

  @override
  int get hashCode => Object.hash(color, kind);

  @override
  String toString() => 'AvatarRingLook($color, ${kind.name})';
}

final _lookups = Expando<Map<String, _Lookup>>();

class _Lookup {
  final DateTime at = DateTime.now();
  final Future<AvatarRingLook?> look;

  /// The ring once looked up, or until then what was known before.
  AvatarRingLook? known;
  bool failed = false;
  _Lookup(this.look, this.known);

  bool get stale =>
      DateTime.now().difference(at) >
      (failed ? avatarRingRetryAfter : avatarRingMaxAge);
}

/// The ring of [userId] as last looked up, or null.
AvatarRingLook? knownAvatarRing(Client client, String userId) =>
    _lookups[client]?[userId]?.known;

/// The ring [userId] has chosen, or null for none (or when it can't be
/// looked up). Kept in memory, so a screen full of someone's avatars asks the
/// server once; [fresh] asks again at once.
///
/// It reads the fields one by one rather than the whole profile: the SDK
/// can't read a profile whose `avatar_url` isn't an mxc URI.
Future<AvatarRingLook?> avatarRingLook(
  Client client,
  String userId, {
  bool fresh = false,
}) {
  final lookups = _lookups[client] ??= {};
  final before = lookups[userId];
  if (!fresh && before != null && !before.stale) return before.look;
  final completer = Completer<AvatarRingLook?>();
  final lookup = lookups[userId] = _Lookup(completer.future, before?.known);
  _lookUp(client, userId).then((result) {
    final (look, failed) = result;
    final earlier = lookup.known;
    lookup.failed = failed;
    // Without an answer, keep showing what was known
    if (!failed) lookup.known = look;
    completer.complete(lookup.known);
    if (before != null && lookup.known != earlier) avatarRingChanges.value++;
  });
  return lookup.look;
}

/// Whether [e] is no answer about the field at all, like any error that
/// isn't the server's: asked too often.
bool _noAnswer(Object e) =>
    e is! MatrixException || e.error == MatrixError.M_LIMIT_EXCEEDED;

/// The ring, and whether the lookup failed without an answer.
Future<(AvatarRingLook?, bool)> _lookUp(Client client, String userId) async {
  final Color? color;
  try {
    color = avatarRingFromProfile(
      await client.getProfileField(userId, avatarRingField),
    );
  } catch (e) {
    if (_noAnswer(e)) {
      Logs().d('Could not look up the avatar ring of $userId', e);
      return (null, true);
    }
    // The server answered: M_NOT_FOUND when they have no ring; anything
    // else (a server without custom fields, say) counts as none too
    if ((e as MatrixException).error != MatrixError.M_NOT_FOUND) {
      Logs().d('No avatar ring for $userId', e);
    }
    return (null, false);
  }
  if (color == null) return (null, false);
  try {
    final style = await client.getProfileField(userId, avatarRingStyleField);
    return switch (avatarRingKindFromProfile(style)) {
      // Only with its own colour: another, and an app before 1.1.46 has
      // picked a plain ring since
      AvatarRingKind.christmas when color != AvatarRingLook.christmas.color => (
        AvatarRingLook(color),
        false,
      ),
      final kind => (AvatarRingLook(color, kind), false),
    };
  } catch (e) {
    if (_noAnswer(e)) {
      Logs().d('Could not look up the avatar ring of $userId', e);
      return (null, true);
    }
    // No kind (or set by an app before 1.1.46): a plain ring
    return (AvatarRingLook(color), false);
  }
}

/// The ring colour in a profile's [fields], or null when there is none or
/// it isn't one of the colours the app offers.
Color? avatarRingFromProfile(Map<String, Object?> fields) {
  final value = fields[avatarRingField];
  return value is int && chatColorChoices.contains(value) ? Color(value) : null;
}

/// The ring's kind in a profile's [fields]: plain unless it names another.
AvatarRingKind avatarRingKindFromProfile(Map<String, Object?> fields) {
  final value = fields[avatarRingStyleField];
  return AvatarRingKind.values.asNameMap()[value] ?? AvatarRingKind.plain;
}

Future<void> _deleteField(Client client, String field) async {
  try {
    await client.deleteProfileField(client.userID!, field);
  } on MatrixException catch (e) {
    // Not there: nothing to delete
    if (e.error != MatrixError.M_NOT_FOUND) rethrow;
  }
}

Future<void> _setField(Client client, String field, Object value) =>
    client.setProfileField(client.userID!, field, {field: value});

/// Gives your own picture the ring [look], or takes it away with null,
/// unless it already has that ring ([current]).
///
/// It takes several writes, in an order that leaves a plain ring, or none,
/// when not all get through. The kind is always cleared first, as another
/// app may have set it.
Future<void> changeAvatarRing(
  Client client,
  AvatarRingLook? current,
  AvatarRingLook? look,
) async {
  if (look == current) return;
  if (look == null) {
    await _deleteField(client, avatarRingField);
    await _deleteField(client, avatarRingStyleField);
  } else {
    await _deleteField(client, avatarRingStyleField);
    await _setField(client, avatarRingField, look.color.toARGB32());
    if (look.kind != AvatarRingKind.plain) {
      await _setField(client, avatarRingStyleField, look.kind.name);
    }
  }
  // Your own avatars change at once
  await avatarRingLook(client, client.userID!, fresh: true);
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
  Future<AvatarRingLook?>? _lookup;
  Client? _client;
  AvatarRingLook? _look;

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
      _look = null;
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
    final look = knownAvatarRing(_client!, userId);
    if (look != _look) setState(() => _look = look);
  }

  Client _clientOf() => widget.client ?? Matrix.of(context).client;

  void _lookUp() {
    final userId = widget.userId;
    if (userId == null || !userId.isValidMatrixIdStrict()) {
      _lookup = null;
      _look = null;
      return;
    }
    final client = _client = _clientOf();
    // Known already, so a new avatar shows its ring from the first frame
    _look = knownAvatarRing(client, userId) ?? _look;
    final lookup = _lookup = avatarRingLook(client, userId);
    lookup.then((look) {
      if (mounted && identical(lookup, _lookup) && look != _look) {
        setState(() => _look = look);
      }
    });
  }

  @override
  Widget build(BuildContext context) =>
      gruppechatRingedAvatar(widget.size, _look, widget.child);
}

/// The width of the ring around an avatar [size] across.
double _ringWidth(double size) => max(2.0, size / 16);

/// [child] of [size] inside the ring [look], [size] across in all; just
/// [child] without a [look]. The tree is the same either way, so a ring
/// coming, going or changing doesn't load the picture again.
Widget gruppechatRingedAvatar(double size, AvatarRingLook? look, Widget child) {
  final width = look == null ? 0.0 : _ringWidth(size);
  return CustomPaint(
    key: avatarRingKey,
    // In front, so sparkles may reach over the edge of the picture
    foregroundPainter: look == null ? null : AvatarRingPainter(look),
    child: Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(width * 1.5),
      child: FittedBox(child: child),
    ),
  );
}

/// The key of the [CustomPaint] that draws the ring, for tests. It is there
/// with or without a ring; without one it has no foreground painter.
const avatarRingKey = ValueKey('gruppechat-avatar-ring');

/// Below this size across, glitter and Christmas rings are drawn plain: the
/// sparkles and stripes would only be noise.
const avatarRingDetailSize = 24.0;

// The Christmas backgrounds' red, green and gold (group_state.dart)
const _christmasRed = Color(0xFFB71C1C);
const _christmasGreen = Color(0xFF1B5E20);
const _gold = Color(0xFFFFD54F);

/// Draws the ring [look] at the edge of what it paints, inside it. Still,
/// not moving, and the same every time: an avatar is in every row of the
/// chat list.
class AvatarRingPainter extends CustomPainter {
  final AvatarRingLook look;

  const AvatarRingPainter(this.look);

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final width = _ringWidth(side);
    final center = size.center(Offset.zero);
    final radius = side / 2 - width / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    final detailed = side >= avatarRingDetailSize;
    switch (look.kind) {
      case AvatarRingKind.glitter when detailed:
        // The colour with a sheen going round it, and sparkles on it
        stroke.shader = SweepGradient(
          colors: [
            look.color,
            Color.lerp(look.color, Colors.white, 0.6)!,
            look.color,
            Color.lerp(look.color, Colors.black, 0.25)!,
            look.color,
          ],
        ).createShader(rect);
        canvas.drawCircle(center, radius, stroke);
        _sparkles(canvas, center, side, width, 6);
      case AvatarRingKind.christmas when detailed:
        // Red and green stripes with gold dots between them
        const stripes = 12;
        const sweep = 2 * pi / stripes;
        for (var i = 0; i < stripes; i++) {
          stroke.color = i.isEven ? _christmasRed : _christmasGreen;
          canvas.drawArc(rect, -pi / 2 + i * sweep, sweep, false, stroke);
        }
        final dot = Paint()..color = _gold;
        for (var i = 0; i < stripes; i++) {
          final a = -pi / 2 + i * sweep;
          canvas.drawCircle(
            center + Offset(cos(a), sin(a)) * radius,
            width * 0.35,
            dot,
          );
        }
        _sparkles(canvas, center, side, width, 2);
      // Too small for more: the colour, which for Christmas is the red an
      // app before 1.1.46 shows
      case _:
        canvas.drawCircle(center, radius, stroke..color = look.color);
    }
  }

  /// [count] sparkles at fixed places round the ring, pale gold and white
  /// in turn, like the glitter effect's. A dark gold edge makes them show
  /// on a gold or pale ring too. They sit just inside the ring, reaching
  /// over the edge of the picture, so none of them goes outside the avatar.
  void _sparkles(
    Canvas canvas,
    Offset center,
    double side,
    double width,
    int count,
  ) {
    final fill = Paint();
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(0.5, width / 6)
      ..color = gruppechatGlitterEdgeGold;
    for (var i = 0; i < count; i++) {
      final a = -pi / 4 + 2 * pi * i / count;
      final c = center + Offset(cos(a), sin(a)) * (side / 2 - width * 1.5);
      final star = gruppechatSparkle(c, width * (i.isEven ? 1.5 : 1.1), 0);
      canvas.drawPath(
        star,
        fill..color = i.isEven ? gruppechatGlitterPaleGold : Colors.white,
      );
      canvas.drawPath(star, edge);
    }
  }

  // The size is the widget's, so a change of size repaints anyway
  @override
  bool shouldRepaint(AvatarRingPainter old) => old.look != look;
}

/// The ring picked by tapping the swatch [color] in the ring dialog, with
/// [glitter] on or off.
AvatarRingLook avatarRingFromSwatch(int color, {required bool glitter}) =>
    AvatarRingLook(
      Color(color),
      glitter ? AvatarRingKind.glitter : AvatarRingKind.plain,
    );

/// Whether the swatch [color] is marked as the [current] ring in the ring
/// dialog: the Christmas ring has a tile of its own.
bool avatarRingSwatchIsCurrent(AvatarRingLook? current, int color) =>
    current != null &&
    current.kind != AvatarRingKind.christmas &&
    current.color.toARGB32() == color;

/// Asks for a ring for your own picture, with [current] marked. The answer
/// is a record, so that "no ring" ((null,)) differs from cancelling (null).
/// A colour is picked with one tap, with glitter when the switch is on.
Future<(AvatarRingLook?,)?> _showAvatarRingChoiceDialog(
  BuildContext context,
  AvatarRingLook? current,
) {
  var glitter = current?.kind == AvatarRingKind.glitter;
  final christmas = current?.kind == AvatarRingKind.christmas;
  return showDialog<(AvatarRingLook?,)>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final l10n = L10n.of(context);
        return AlertDialog(
          title: Text(l10n.gruppechatAvatarRing),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.gruppechatAvatarRingDescription),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.auto_awesome),
                  title: Text(l10n.gruppechatAvatarRingGlitter),
                  value: glitter,
                  onChanged: (value) => setState(() => glitter = value),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final color in chatColorChoices)
                      GroupColorSwatch(
                        color: Color(color),
                        selected: avatarRingSwatchIsCurrent(current, color),
                        onTap: () => Navigator.of(
                          context,
                        ).pop((avatarRingFromSwatch(color, glitter: glitter),)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const SizedBox.square(
                    dimension: 40,
                    child: CustomPaint(
                      painter: AvatarRingPainter(AvatarRingLook.christmas),
                    ),
                  ),
                  title: Text(l10n.gruppechatAvatarRingChristmas),
                  trailing: christmas ? const Icon(Icons.check) : null,
                  onTap: () =>
                      Navigator.of(context).pop((AvatarRingLook.christmas,)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop((null,)),
              child: Text(l10n.gruppechatAvatarRingNone),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel),
            ),
          ],
        );
      },
    ),
  );
}

/// Lets you pick a ring for your own picture, or take it away.
Future<void> showAvatarRingDialog(BuildContext context, Client client) async {
  // Fresh, as another of your apps may have changed it
  final current = await avatarRingLook(client, client.userID!, fresh: true);
  if (!context.mounted) return;
  final picked = await _showAvatarRingChoiceDialog(context, current);
  if (picked == null || !context.mounted) return;
  await showFutureLoadingDialog(
    context: context,
    future: () => changeAvatarRing(client, current, picked.$1),
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
