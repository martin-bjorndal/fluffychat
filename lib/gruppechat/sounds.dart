// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:matrix/matrix.dart';

/// The notification sounds a chat can have instead of the usual one. Made by
/// scripts/gruppechat_sounds.py, which also puts them where Android takes
/// a notification's sound from (res/raw).
enum GruppechatSound {
  bell('gc_bjelle'),
  ping('gc_pling'),
  chimes('gc_klokkespill'),
  bubble('gc_boble'),
  flute('gc_floyte'),
  doubleBeep('gc_dobbeltpip');

  /// The file's name, as an Android raw resource and in assets/sounds/.
  final String file;

  const GruppechatSound(this.file);

  String get asset => 'assets/sounds/$file.wav';

  String label(L10n l10n) => switch (this) {
    bell => l10n.gruppechatSoundBell,
    ping => l10n.gruppechatSoundPing,
    chimes => l10n.gruppechatSoundChimes,
    bubble => l10n.gruppechatSoundBubble,
    flute => l10n.gruppechatSoundFlute,
    doubleBeep => l10n.gruppechatSoundDoubleBeep,
  };

  /// Android fixes a notification channel's sound once it exists, so each
  /// sound has a channel of its own, shared by the chats that use it.
  String get channelId => 'gruppechat_sound_$name';

  static GruppechatSound? byName(Object? name) =>
      values.where((sound) => sound.name == name).firstOrNull;
}

/// Where a chat's notification sound is kept: in the room's account data,
/// so it is the same on all of someone's devices, and only theirs.
const gruppechatSoundAccountData = 'im.gruppechat.sound';

/// The notification sound chosen for [room], or null for the usual one.
GruppechatSound? gruppechatChatSound(Room room) => GruppechatSound.byName(
  room.roomAccountData[gruppechatSoundAccountData]?.content['sound'],
);

/// Chooses [sound] for [room]'s notifications; null goes back to the usual.
Future<void> gruppechatSetChatSound(Room room, GruppechatSound? sound) =>
    room.client.setAccountDataPerRoom(
      room.client.userID!,
      room.id,
      gruppechatSoundAccountData,
      {if (sound != null) 'sound': sound.name},
    );

/// The Android notification channel a message in [room] is shown in: the
/// usual one, or the one for the chat's own sound, with the raw resource
/// it plays.
({String id, String name, String? sound}) gruppechatNotificationChannel(
  Room room, {
  required String usualId,
  required String usualName,
  required L10n l10n,
}) {
  final sound = gruppechatChatSound(room);
  if (sound == null) return (id: usualId, name: usualName, sound: null);
  return (
    id: sound.channelId,
    name: '$usualName: ${sound.label(l10n)}',
    sound: sound.file,
  );
}

/// Whether [event], which just came into the chat on screen, gets the
/// sound of a message coming in: a message from someone else, sent after
/// the chat was opened at [openedAt], not one loaded from history.
bool gruppechatPlaysReceivedSound(Event event, DateTime openedAt) =>
    event.senderId != event.room.client.userID &&
    {
      EventTypes.Message,
      EventTypes.Sticker,
      EventTypes.Encrypted,
    }.contains(event.type) &&
    !event.originServerTs.isBefore(openedAt);

/// Plays the app's short sounds, unless [AppSettings.gruppechatChatSounds]
/// is off for the chat sounds.
abstract final class GruppechatSounds {
  static AudioPlayer? _player;

  static Future<void> play(String asset) async {
    try {
      final player = _player ??= AudioPlayer();
      await player.setAsset(asset);
      await player.seek(Duration.zero);
      // Not awaited: it completes only when the sound has played
      player.play();
    } catch (e, s) {
      // A sound is never worth an error; tests have no audio at all
      if (!kDebugMode) Logs().w('Could not play $asset', e, s);
    }
  }

  static void sent() {
    if (AppSettings.gruppechatChatSounds.value) {
      play('assets/sounds/gc_sent.wav');
    }
  }

  static void received() {
    if (AppSettings.gruppechatChatSounds.value) {
      play('assets/sounds/gc_received.wav');
    }
  }
}

/// Lets someone choose [room]'s notification sound, playing each one they
/// tap, and saves the choice.
Future<void> gruppechatChooseChatSound(BuildContext context, Room room) async {
  final l10n = L10n.of(context);
  final current = gruppechatChatSound(room);
  final chosen = await showModalBottomSheet<({GruppechatSound? sound})>(
    context: context,
    builder: (context) {
      Widget option(GruppechatSound? sound) => ListTile(
        key: Key('sound_${sound?.name ?? 'default'}'),
        title: Text(sound?.label(l10n) ?? l10n.gruppechatDefaultSound),
        trailing: sound == current ? const Icon(Icons.check) : null,
        onTap: () {
          GruppechatSounds.play(
            sound?.asset ?? 'assets/sounds/notification.mp3',
          );
          Navigator.of(context).pop((sound: sound));
        },
      );
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  l10n.gruppechatNotificationSound,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              option(null),
              for (final sound in GruppechatSound.values) option(sound),
            ],
          ),
        ),
      );
    },
  );
  if (chosen == null || chosen.sound == current) return;
  await gruppechatSetChatSound(room, chosen.sound);
}
