// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

import 'package:fluffychat/gruppechat/sounds.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
// The same Markdown as any message the app sends
// ignore: implementation_imports
import 'package:matrix/src/utils/markdown.dart';

/// What a message can be sent with: an animation over the chat, with a
/// sound, for whoever has the chat open when it comes in or opens it
/// unread.
enum GruppechatEffect {
  confetti('🎉', 'gc_effect_konfetti'),
  hearts('❤️', 'gc_effect_hjerter'),
  balloons('🎈', 'gc_effect_ballonger'),
  fireworks('🎆', 'gc_effect_fyrverkeri'),
  cats('🐱', 'gc_effect_katter', floats: true);

  final String emoji;
  final String sound;

  /// Whether it is drawn as its [emoji] floating up, as a message of only
  /// a [gruppechatFloatingEmojis] emoji is.
  final bool floats;

  const GruppechatEffect(this.emoji, this.sound, {this.floats = false});

  String get asset => 'assets/sounds/$sound.wav';

  String label(L10n l10n) => switch (this) {
    confetti => l10n.gruppechatEffectConfetti,
    hearts => l10n.gruppechatEffectHearts,
    balloons => l10n.gruppechatEffectBalloons,
    fireworks => l10n.gruppechatEffectFireworks,
    cats => l10n.gruppechatEffectCats,
  };

  static GruppechatEffect? byName(Object? name) =>
      values.where((effect) => effect.name == name).firstOrNull;
}

/// Where in a message its effect is named. Other Matrix apps ignore it and
/// show the message as usual.
const gruppechatEffectKey = 'im.gruppechat.effect';

/// The effect [event] was sent with, if any.
GruppechatEffect? gruppechatEffectOf(Event event) =>
    event.type == EventTypes.Message && !event.redacted
    ? GruppechatEffect.byName(event.content[gruppechatEffectKey])
    : null;

/// The emojis that, sent on their own, float up over the chat as they do
/// in Messenger: hearts and loving faces.
const gruppechatFloatingEmojis = [
  '❤️‍🔥', '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '🩷', '🩵', //
  '🩶', '💕', '💞', '💓', '💗', '💖', '💘', '💝', '💟', '🥰', '😍', '😘', '😻',
];

/// The emoji that floats up for [event]: a text message, not an edit and
/// without an effect, that is one to three of one of
/// [gruppechatFloatingEmojis] and nothing else. ❤ counts as ❤️, as some
/// keyboards leave out the variation selector.
String? gruppechatFloatingEmojiOf(Event event) {
  if (event.type != EventTypes.Message ||
      event.redacted ||
      event.messageType != MessageTypes.Text ||
      event.relationshipType == RelationshipTypes.edit ||
      event.content[gruppechatEffectKey] != null) {
    return null;
  }
  // Longer than three of any of them with spaces: not worth looking at
  if (event.body.length > 40) return null;
  final body = _bare(event.body);
  for (var n = 1; n <= 3; n++) {
    if (body.length % n != 0) continue;
    final one = body.substring(0, body.length ~/ n);
    if (one * n == body) {
      if (_floatingByBare[one] case final emoji?) return emoji;
    }
  }
  return null;
}

final _invisible = RegExp(r'[\s\uFE0F]');

String _bare(String text) => text.replaceAll(_invisible, '');

final _floatingByBare = {
  for (final emoji in gruppechatFloatingEmojis) _bare(emoji): emoji,
};

/// What [played] in [gruppechatEffectToPlay] knows a message by: the id
/// the sender's phone gave it, if it has one, as one's own message has
/// another id until the server has it.
String gruppechatPlayKey(Event event) => event.transactionId ?? event.eventId;

/// What plays over the chat for a message: the effect it was sent with, if
/// any, and the emoji its animation shows; without an effect it is a quiet
/// burst of a [gruppechatFloatingEmojiOf] emoji.
typedef GruppechatPlay = ({GruppechatEffect? effect, String emoji});

/// What plays over the chat for [event], if anything.
GruppechatPlay? gruppechatPlayOf(Event event) {
  if (gruppechatEffectOf(event) case final effect?) {
    return (effect: effect, emoji: effect.emoji);
  }
  if (gruppechatFloatingEmojiOf(event) case final emoji?) {
    return (effect: null, emoji: emoji);
  }
  return null;
}

/// Sends [text] to [room] with [effect], formatted and with its mentions
/// as Room.sendTextEvent sends a message.
Future<String?> gruppechatSendWithEffect(
  Room room,
  String text,
  GruppechatEffect effect, {
  Event? inReplyTo,
  String? threadRootEventId,
  String? threadLastEventId,
}) {
  final content = <String, Object?>{
    'msgtype': MessageTypes.Text,
    'body': text,
    gruppechatEffectKey: effect.name,
  };
  final mentions = <String>{
    for (final word in text.split(RegExp(r'\s+')))
      if (word.startsWith('@'))
        // Without the punctuation after a name, as in «@bob!»
        ?_mentioned(room, word.replaceFirst(RegExp(r'[.,!?;:)]+$'), '')),
    ?inReplyTo?.senderId,
  }..remove(room.client.userID);
  final mentionsRoom = text.split(RegExp(r'\s+')).contains('@room');
  if (mentions.isNotEmpty || mentionsRoom) {
    content['m.mentions'] = {
      if (mentionsRoom) 'room': true,
      if (mentions.isNotEmpty) 'user_ids': mentions.toList(),
    };
  }
  final html = markdown(
    text,
    getEmotePacks: () => room.getImagePacksFlat(ImagePackUsage.emoticon),
    getMention: room.getMention,
    convertLinebreaks: room.client.convertLinebreaksInFormatting,
  );
  // Plain text comes back with only line breaks and escaped characters
  if (RegExp(r'<(?!br />)[a-zA-Z/]').hasMatch(html)) {
    content['format'] = 'org.matrix.custom.html';
    content['formatted_body'] = html;
  }
  return room.sendEvent(
    content,
    inReplyTo: inReplyTo,
    threadRootEventId: threadRootEventId,
    threadLastEventId: threadLastEventId,
  );
}

String? _mentioned(Room room, String word) =>
    word.isValidMatrixIdStrict() ? word : room.getMention(word);

/// The message in [newestFirst], the chat's timeline, whose effect should
/// play now: the newest one with an effect or a floating emoji
/// ([gruppechatPlayOf]) not [played] yet that came in
/// after the chat opened at [openedAt], or was among the [unreadAtOpen]
/// newest messages from others when it opened. Of floating emojis only the
/// newest plays, so a row of hearts floats once. [played] holds
/// [gruppechatPlayKey]s.
Event? gruppechatEffectToPlay(
  List<Event> newestFirst, {
  required Set<String> played,
  required DateTime openedAt,
  required int unreadAtOpen,
}) {
  final ownId = newestFirst.firstOrNull?.room.client.userID;
  var fromOthers = 0;
  var newerFloats = false;
  for (final event in newestFirst) {
    if (event.type != EventTypes.Message || event.status.isError) continue;
    final mine = event.senderId == ownId;
    final unread = !mine && fromOthers < unreadAtOpen;
    if (!mine) fromOthers++;
    final old = event.originServerTs.isBefore(openedAt);
    // Nothing older is new or unread either
    if (old && !unread && fromOthers >= unreadAtOpen) break;
    final play = gruppechatPlayOf(event);
    if (play == null) continue;
    if (play.effect == null) {
      if (newerFloats) continue;
      newerFloats = true;
    }
    if (played.contains(gruppechatPlayKey(event))) continue;
    return event;
  }
  return null;
}

/// Plays [play] ([gruppechatPlayOf]) over whatever is under it, then
/// removes itself: its effect with the effect's sound, or without one, its
/// emoji floating up without a sound.
class GruppechatEffectOverlay extends StatefulWidget {
  final GruppechatPlay play;
  final VoidCallback onDone;

  const GruppechatEffectOverlay({
    required this.play,
    required this.onDone,
    super.key,
  });

  @override
  State<GruppechatEffectOverlay> createState() =>
      _GruppechatEffectOverlayState();
}

class _GruppechatEffectOverlayState extends State<GruppechatEffectOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..forward().whenComplete(widget.onDone);
  late final GruppechatEffect? _effect = widget.play.effect;

  late final bool _floats = _effect?.floats ?? true;
  late final List<_Particle> _particles = _Particle.many(_effect);

  /// Each particle's emoji, laid out once.
  late final List<TextPainter> _emojis = [
    if (_floats)
      for (final p in _particles)
        TextPainter(
          text: TextSpan(
            text: widget.play.emoji,
            style: TextStyle(fontSize: 30 * p.size),
          ),
          textDirection: TextDirection.ltr,
        )..layout(),
  ];

  @override
  void initState() {
    super.initState();
    if (_effect case final effect?) GruppechatSounds.play(effect.asset);
  }

  @override
  void dispose() {
    _controller.dispose();
    for (final emoji in _emojis) {
      emoji.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) {
      // Only the sound for those who turned animations off
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _floats
              ? _EmojiPainter(_emojis, _particles, _controller.value)
              : _EffectPainter(_effect!, _particles, _controller.value),
        ),
      ),
    );
  }
}

class _Particle {
  /// Where across the screen it starts, 0 to 1.
  final double x;

  /// When it starts, as a share of the animation.
  final double delay;
  final double size;
  final double spin;
  final double drift;
  final Color color;

  _Particle(this.x, this.delay, this.size, this.spin, this.drift, this.color);

  /// How far along its own flight it is at [progress], 0 to 1.
  double lifeAt(double progress) =>
      ((progress - delay) / (1 - delay)).clamp(0.0, 1.0);

  /// 1, going to 0 over the last fifth of its flight [t].
  static double endingAt(double t) => t > 0.8 ? (1 - t) / 0.2 : 1.0;

  static const _party = [
    Color(0xFFFF4F8B),
    Color(0xFFFFC93C),
    Color(0xFF4FC3F7),
    Color(0xFF7CDA6B),
    Color(0xFFB388FF),
    Color(0xFFFF8A50),
  ];

  /// The particles of [effect], or of a floating emoji for null.
  static List<_Particle> many(GruppechatEffect? effect) {
    final random = Random();
    final count = switch (effect) {
      GruppechatEffect.confetti => 90,
      GruppechatEffect.hearts => 28,
      GruppechatEffect.balloons => 14,
      GruppechatEffect.fireworks => 5,
      GruppechatEffect.cats || null => 22,
    };
    return [
      for (var i = 0; i < count; i++)
        _Particle(
          random.nextDouble(),
          random.nextDouble() * 0.35,
          0.6 + random.nextDouble() * 0.8,
          (random.nextDouble() - 0.5) * 12,
          (random.nextDouble() - 0.5) * 0.15,
          effect == GruppechatEffect.hearts
              ? Color.lerp(
                  const Color(0xFFFF4F8B),
                  const Color(0xFFE0115F),
                  random.nextDouble(),
                )!
              : _party[random.nextInt(_party.length)],
        ),
    ];
  }
}

class _EffectPainter extends CustomPainter {
  final GruppechatEffect effect;
  final List<_Particle> particles;
  final double progress;

  _EffectPainter(this.effect, this.particles, this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final t = p.lifeAt(progress);
      if (t <= 0 || t >= 1) continue;
      final fade = _Particle.endingAt(t);
      final paint = Paint()..color = p.color.withValues(alpha: fade);
      switch (effect) {
        case GruppechatEffect.confetti:
          // Falls from the top, turning
          final center = Offset(
            (p.x + p.drift * sin(t * 6)) * size.width,
            -20 + t * (size.height + 40),
          );
          canvas.save();
          canvas.translate(center.dx, center.dy);
          canvas.rotate(p.spin * t);
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset.zero,
              width: 8 * p.size,
              height: 14 * p.size,
            ),
            paint,
          );
          canvas.restore();
        case GruppechatEffect.hearts:
          // Floats up from the bottom
          _heart(
            canvas,
            Offset(
              (p.x + p.drift * sin(t * 8)) * size.width,
              size.height + 30 - t * (size.height + 60),
            ),
            22 * p.size,
            paint,
          );
        case GruppechatEffect.balloons:
          final center = Offset(
            (p.x + p.drift * sin(t * 5)) * size.width,
            size.height + 60 - t * (size.height + 140),
          );
          final r = 26 * p.size;
          canvas.drawLine(
            center + Offset(0, r * 1.2),
            center + Offset(sin(t * 9) * 6, r * 3),
            Paint()
              ..color = paint.color.withValues(alpha: 0.6 * fade)
              ..strokeWidth = 1.5,
          );
          canvas.drawOval(
            Rect.fromCenter(center: center, width: r * 1.7, height: r * 2.1),
            paint,
          );
        case GruppechatEffect.fireworks:
          // Each rocket bursts into a ring of sparks
          final origin = Offset(
            (0.15 + p.x * 0.7) * size.width,
            (0.2 + p.drift.abs() * 2) * size.height,
          );
          const sparks = 18;
          for (var i = 0; i < sparks; i++) {
            final angle = 2 * pi * i / sparks + p.spin;
            final reach = Curves.easeOut.transform(t) * 120 * p.size;
            canvas.drawCircle(
              origin + Offset(cos(angle), sin(angle) + t * 0.6) * reach,
              3.2 * (1 - t) + 1,
              paint,
            );
          }
        case GruppechatEffect.cats:
          // Floating 🐱, drawn by _EmojiPainter
          break;
      }
    }
  }

  void _heart(Canvas canvas, Offset c, double s, Paint paint) {
    final path = Path()
      ..moveTo(c.dx, c.dy + s * 0.35)
      ..cubicTo(
        c.dx - s,
        c.dy - s * 0.3,
        c.dx - s * 0.45,
        c.dy - s,
        c.dx,
        c.dy - s * 0.45,
      )
      ..cubicTo(
        c.dx + s * 0.45,
        c.dy - s,
        c.dx + s,
        c.dy - s * 0.3,
        c.dx,
        c.dy + s * 0.35,
      );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_EffectPainter old) => old.progress != progress;
}

/// Emojis floating up from the bottom, swaying, and fading at the end.
class _EmojiPainter extends CustomPainter {
  final List<TextPainter> emojis;
  final List<_Particle> particles;
  final double progress;

  _EmojiPainter(this.emojis, this.particles, this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < particles.length; i++) {
      final p = particles[i];
      final t = p.lifeAt(progress);
      if (t <= 0 || t >= 1) continue;
      final emoji = emojis[i];
      final center = Offset(
        (p.x + p.drift * sin(t * 7)) * size.width,
        size.height + 30 - t * (size.height + 80),
      );
      // Shrinks away at the end: fading a picture would take a layer each
      final shrink = _Particle.endingAt(t);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.scale(shrink);
      emoji.paint(canvas, Offset(-emoji.width / 2, -emoji.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_EmojiPainter old) => old.progress != progress;
}

/// Asks which effect to send a message with, from the send button's long
/// press.
Future<GruppechatEffect?> gruppechatPickEffect(BuildContext context) {
  final l10n = L10n.of(context);
  return showModalBottomSheet<GruppechatEffect>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              l10n.gruppechatSendWithEffect,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final effect in GruppechatEffect.values)
            ListTile(
              key: Key('effect_${effect.name}'),
              leading: Text(effect.emoji, style: const TextStyle(fontSize: 24)),
              title: Text(effect.label(l10n)),
              onTap: () => Navigator.of(context).pop(effect),
            ),
        ],
      ),
    ),
  );
}
