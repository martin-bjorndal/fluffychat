// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// Messages that disappear. A chat can have a lifetime: everything sent in
/// it while it is set is removed for good once that time is up, with no
/// trace in the chat. The server does the removing
/// (deploy/synapse-modules/gruppechat_lifetime.py), also when nobody's
/// phone is on; the app counts down, and hides what is due before the
/// server gets to it.
///
/// The room state that holds it: `{"lifetime": <milliseconds>}`, or empty
/// when it is off.
const gruppechatLifetimeType = 'im.gruppechat.message_lifetime';

/// In the redaction the server removes an expired event with.
const gruppechatExpiredKey = 'im.gruppechat.expired';

/// Where the app tells the server which uploads belong to a message.
const gruppechatExpiringMediaPath = '_synapse/client/gruppechat/expiring_media';

/// The lifetimes to choose from.
const gruppechatLifetimeChoices = [
  Duration(hours: 1),
  Duration(hours: 3),
  Duration(hours: 6),
  Duration(hours: 12),
  Duration(hours: 24),
];

Duration? _lifetimeIn(Map<String, Object?>? content) {
  final ms = content?['lifetime'];
  return ms is int && ms > 0 ? Duration(milliseconds: ms) : null;
}

/// The lifetime [room] gives what is sent in it now, or null.
Duration? gruppechatMessageLifetime(Room room) =>
    _lifetimeIn(room.getState(gruppechatLifetimeType)?.content);

/// Whether this user may change [room]'s lifetime.
bool gruppechatCanSetMessageLifetime(Room room) =>
    room.canChangeStateEvent(gruppechatLifetimeType);

/// Gives what is sent in [room] from now on [lifetime], or none.
Future<void> gruppechatSetMessageLifetime(Room room, Duration? lifetime) =>
    room.client.setRoomStateWithKey(
      room.id,
      gruppechatLifetimeType,
      '',
      lifetime == null ? {} : {'lifetime': lifetime.inMilliseconds},
    );

/// When [event] disappears, or null when it stays: it was sent while its
/// chat had a lifetime.
DateTime? gruppechatExpiresAt(Event event) {
  if (event.stateKey != null || event.type == EventTypes.Redaction) {
    return null;
  }
  final state = event.room.getState(gruppechatLifetimeType);
  if (state is! Event) return null;
  // Changed after it was sent: what it was before then
  final lifetime = _lifetimeIn(
    state.originServerTs.isAfter(event.originServerTs)
        ? state.prevContent
        : state.content,
  );
  return lifetime == null ? null : event.originServerTs.add(lifetime);
}

/// Whether [event] has disappeared: its time is up, or the server has
/// already removed it.
bool gruppechatIsGone(Event event, {DateTime? now}) {
  if (event.redacted) {
    return event.redactedBecause?.content[gruppechatExpiredKey] == true;
  }
  final expiresAt = gruppechatExpiresAt(event);
  return expiresAt != null && !(now ?? DateTime.now()).isBefore(expiresAt);
}

/// How long a notification about [event] may stay, in milliseconds: until
/// the message disappears. Null for one that stays.
int? gruppechatNotificationTimeout(Event event, {DateTime? now}) {
  final expiresAt = gruppechatExpiresAt(event);
  if (expiresAt == null) return null;
  final left = expiresAt.difference(now ?? DateTime.now()).inMilliseconds;
  return left < 1 ? 1 : left;
}

/// The files [event] was sent with, as mxc URLs: the file itself and its
/// thumbnail, encrypted or not.
List<String> gruppechatMediaOf(Event event) {
  if (event.type != EventTypes.Message) return [];
  final content = event.content;
  final info = content.tryGetMap<String, Object?>('info');
  return {
    content.tryGet<String>('url'),
    content.tryGetMap<String, Object?>('file')?.tryGet<String>('url'),
    info?.tryGet<String>('thumbnail_url'),
    info?.tryGetMap<String, Object?>('thumbnail_file')?.tryGet<String>('url'),
  }.nonNulls.toList();
}

/// Tells the server which uploads go with [event], one of this user's own
/// messages that disappears, so they are deleted with it. The server can't
/// see them in an encrypted message. Returns how many it took.
Future<int> gruppechatRegisterExpiringMedia(Event event) async {
  final client = event.room.client;
  if (event.senderId != client.userID ||
      !event.status.isSent ||
      gruppechatExpiresAt(event) == null) {
    return 0;
  }
  final media = gruppechatMediaOf(event);
  final homeserver = client.homeserver;
  if (media.isEmpty || homeserver == null) return 0;
  final response = await client.httpClient.post(
    homeserver.resolve(gruppechatExpiringMediaPath),
    headers: {
      'Authorization': 'Bearer ${client.accessToken}',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({'event_id': event.eventId, 'media': media}),
  );
  if (response.statusCode != 200) {
    throw Exception('The server answered ${response.statusCode}');
  }
  return (jsonDecode(response.body) as Map)['taken'] as int? ?? 0;
}

/// Tells the server about the files of every disappearing message this
/// user sends, from any device, as they come back from the server.
class GruppechatExpiringMedia {
  final Client client;
  StreamSubscription<Event>? _subscription;

  GruppechatExpiringMedia(this.client);

  void start() => _subscription ??= client.onTimelineEvent.stream.listen(
    (event) => gruppechatRegisterExpiringMedia(event).catchError((e, s) {
      Logs().w('Could not tie files to ${event.eventId}', e, s);
      return 0;
    }),
  );

  void cancel() {
    _subscription?.cancel();
    _subscription = null;
  }
}

/// How long until [expiresAt], as short as the chat shows it: «5 t»,
/// «12 min».
String gruppechatTimeLeft(L10n l10n, DateTime expiresAt, {DateTime? now}) {
  final left = expiresAt.difference(now ?? DateTime.now());
  if (left.inMinutes >= 60) {
    return l10n.gruppechatHoursLeft((left.inMinutes / 60).ceil());
  }
  return l10n.gruppechatMinutesLeft(left.inMinutes < 1 ? 1 : left.inMinutes);
}

/// A lifetime as the settings show it.
String gruppechatLifetimeLabel(L10n l10n, Duration? lifetime) =>
    lifetime == null
    ? l10n.gruppechatLifetimeOff
    : l10n.gruppechatLifetimeHours(lifetime.inHours);

/// The time left of a message that disappears, next to when it was sent.
class GruppechatTimeLeft extends StatefulWidget {
  final DateTime expiresAt;
  final Color? color;
  final List<Shadow>? shadows;

  const GruppechatTimeLeft({
    required this.expiresAt,
    this.color,
    this.shadows,
    super.key,
  });

  @override
  State<GruppechatTimeLeft> createState() => _GruppechatTimeLeftState();
}

class _GruppechatTimeLeftState extends State<GruppechatTimeLeft> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: widget.color,
      fontSize: 11,
      shadows: widget.shadows,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(' ', style: style),
        Icon(
          Icons.timer_outlined,
          size: 11,
          color: widget.color,
          shadows: widget.shadows,
        ),
        Text(
          ' ${gruppechatTimeLeft(L10n.of(context), widget.expiresAt)}',
          style: style,
        ),
      ],
    );
  }
}

/// Asks how long what is sent in [room] should last, from the chat's
/// details.
Future<void> gruppechatChooseMessageLifetime(
  BuildContext context,
  Room room,
) async {
  final l10n = L10n.of(context);
  final current = gruppechatMessageLifetime(room);
  final chosen = await showModalBottomSheet<({Duration? lifetime})>(
    context: context,
    builder: (context) {
      Widget option(Duration? lifetime) => ListTile(
        key: Key('lifetime_${lifetime?.inHours ?? 'off'}'),
        title: Text(gruppechatLifetimeLabel(l10n, lifetime)),
        trailing: lifetime == current ? const Icon(Icons.check) : null,
        onTap: () => Navigator.of(context).pop((lifetime: lifetime)),
      );
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  l10n.gruppechatMessageLifetime,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                subtitle: Text(l10n.gruppechatMessageLifetimeDescription),
              ),
              option(null),
              for (final lifetime in gruppechatLifetimeChoices)
                option(lifetime),
            ],
          ),
        ),
      );
    },
  );
  if (chosen == null || chosen.lifetime == current) return;
  await gruppechatSetMessageLifetime(room, chosen.lifetime);
}
