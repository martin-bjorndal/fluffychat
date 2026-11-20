// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:audio_session/audio_session.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/gruppechat/web_audio_session.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:just_audio/just_audio.dart';
import 'package:material_ui/material_ui.dart';
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
  doubleBeep('gc_dobbeltpip'),
  meow('gc_mjau'),
  kitten('gc_kattunge');

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
    meow => l10n.gruppechatSoundMeow,
    kitten => l10n.gruppechatSoundKitten,
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

/// The notification channel for messages while the app is open: heads-up
/// and vibration, but no sound of its own.
const gruppechatOnScreenChannelId = 'gruppechat_on_screen';

/// The channel the push helper shows a message in [room] in, and whether
/// the app plays its sound itself ([soundInApp]).
///
/// While the app is open on an Android phone ([appOnScreen], see
/// [gruppechatAppOnScreen]), it is the quiet channel for messages while the
/// app is open, and the app plays the chat's sound
/// ([GruppechatSounds.notification]): some phones, OnePlus' among them,
/// didn't sound a notification of the app on screen (reported in 1.1.29).
/// Not when the person has quieted the chat's own channel in Android's
/// settings: then it stays there, quiet.
Future<({String id, String name, String? sound, bool soundInApp})>
gruppechatPushChannel(
  Room room, {
  required String usualId,
  required String usualName,
  required L10n l10n,
  required bool appOnScreen,
}) async {
  final usual = gruppechatNotificationChannel(
    room,
    usualId: usualId,
    usualName: usualName,
    l10n: l10n,
  );
  if (appOnScreen && await gruppechatChannelSounds(usual.id, room.id)) {
    return (
      id: gruppechatOnScreenChannelId,
      name: l10n.gruppechatOnScreenChannel,
      sound: null,
      soundInApp: true,
    );
  }
  return (
    id: usual.id,
    name: usual.name,
    sound: usual.sound,
    soundInApp: false,
  );
}

/// Whether the app is open on an Android phone, where it plays the sound of
/// a message's notification itself. False without a Flutter binding, as in
/// the push helper's background isolate.
bool gruppechatAppOnScreen() {
  if (!PlatformInfos.isAndroid) return false;
  try {
    return WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  } catch (_) {
    return false;
  }
}

/// Whether a notification of [roomId] in [channelId] would make a sound on
/// this phone: the person hasn't turned off the app's notifications, nor
/// the sound of the channel or of the chat's conversation in it (which
/// Android keeps as a channel of its own, its id holding both) in Android's
/// settings. A channel that isn't made yet would sound.
Future<bool> gruppechatChannelSounds(String channelId, String roomId) async {
  final android = FlutterLocalNotificationsPlatform.instance;
  if (android is! AndroidFlutterLocalNotificationsPlugin) return true;
  try {
    final (enabled, channels) = await (
      android.areNotificationsEnabled(),
      android.getNotificationChannels(),
    ).wait;
    if (enabled == false) return false;
    return (channels ?? [])
        .where(
          (channel) =>
              channel.id == channelId ||
              (channel.id.startsWith(channelId) && channel.id.endsWith(roomId)),
        )
        .every(
          (channel) =>
              channel.playSound &&
              channel.importance.value >= Importance.defaultImportance.value,
        );
  } catch (e, s) {
    Logs().w('Could not read the notification channel $channelId', e, s);
    return true;
  }
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

/// The app's usual notification sound, for a chat without one of its own.
const gruppechatUsualSoundAsset = 'assets/sounds/notification.mp3';

/// Plays the app's short sounds, at [AppSettings.gruppechatSoundVolume]. The
/// sound of getting a message in the open chat follows
/// [AppSettings.gruppechatChatSounds]; a notification's sound while the app
/// is open does not, as it stands in for the notification's own. Sending a
/// message makes no sound: until 1.1.41 it did, and people took it for a
/// notification of their own message.
///
/// On Android they play as notification sounds: at the phone's notification
/// volume, quiet in silent mode and Do Not Disturb, and without taking audio
/// focus, so music or a call goes on. Before 1.1.30 they played as media, at
/// the media volume, which people found far too loud.
///
/// None of them, previews in the settings included, play while an Android
/// phone is on silent or vibrate: the app checks ([phoneQuiet]). In Safari
/// 17+ on an iPhone they follow the silent switch
/// ([gruppechatAmbientSession]), except during a call or a voice message
/// ([otherAudioPlaying]), which would follow it too. Other browsers can't
/// tell the phone's sound mode.
abstract final class GruppechatSounds {
  static Future<AudioPlayer>? _player;
  static String? _asset;
  static DateTime? _lastNotification;

  /// For tests, which have no audio: gets each sound that would play, and
  /// its volume, instead of the player.
  @visibleForTesting
  static void Function(String asset, double volume)? onPlay;

  /// For tests, which have no phone: whether it is on silent or vibrate
  /// (see [phoneQuiet]).
  @visibleForTesting
  static Future<bool> Function()? onPhoneQuiet;

  /// Whether the phone is set to make no sounds: on silent or vibrate, or
  /// with the notification volume all the way down. Only Android tells;
  /// elsewhere, and if it can't be read, false. Reported in 1.1.40: the
  /// sounds of the open chat played on a phone on silent, although they
  /// play as notification sounds, so the app checks for itself.
  static Future<bool> phoneQuiet() async {
    if (onPhoneQuiet case final onPhoneQuiet?) return onPhoneQuiet();
    if (!PlatformInfos.isAndroid) return false;
    try {
      final audio = AndroidAudioManager();
      final (mode, volume) = await (
        audio.getRingerMode(),
        audio.getStreamVolume(AndroidStreamType.notification),
      ).wait;
      return mode != AndroidRingerMode.normal || volume <= 0;
    } catch (e, s) {
      if (!kDebugMode) {
        Logs().w('Could not read whether the phone is on silent', e, s);
      }
      return false;
    }
  }

  /// Whether other audio of the app plays, a call or a voice message; set
  /// by MatrixState ([gruppechatAudioInUse]). Then a sound doesn't change the
  /// web page's audio session, which would make that audio follow the
  /// silent switch too. Null, before MatrixState, counts as nothing.
  static bool Function()? otherAudioPlaying;

  /// For tests: forgets when a notification's sound last played.
  @visibleForTesting
  static void resetNotificationPause() => _lastNotification = null;

  static Future<AudioPlayer> _newPlayer() async {
    if (!PlatformInfos.isAndroid) return AudioPlayer();
    final player = AudioPlayer(
      handleAudioSessionActivation: false,
      androidApplyAudioAttributes: false,
    );
    await player.setAndroidAudioAttributes(
      const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.sonification,
        usage: AndroidAudioUsage.notification,
      ),
    );
    return player;
  }

  static Future<void> play(String asset) async {
    // The setting first: it costs no call to the phone
    if (AppSettings.gruppechatSoundVolume.value <= 0) return;
    if (await phoneQuiet()) return;
    await _playNow(asset);
  }

  static Future<void> _playNow(String asset) async {
    final volume = AppSettings.gruppechatSoundVolume.value;
    if (volume <= 0) return;
    if (onPlay case final onPlay?) return onPlay(asset, volume);
    try {
      final player = await (_player ??= _newPlayer().catchError((Object e) {
        // Tried again with the next sound
        _player = null;
        throw e;
      }));
      await player.setVolume(volume);
      if (asset != _asset) {
        _asset = null;
        await player.setAsset(asset);
        _asset = asset;
      }
      // Before the seek, which is what starts the sound again on a player
      // that still counts as playing
      if (kIsWeb && otherAudioPlaying?.call() != true) {
        gruppechatAmbientSession.hold(
          (player.duration ?? const Duration(seconds: 3)) +
              const Duration(seconds: 1),
        );
      }
      await player.seek(Duration.zero);
      // Not awaited: the one player plays every sound, and play() returns
      // only when it is paused, or at once while it counts as playing
      player.play();
    } catch (e, s) {
      // A sound is never worth an error; tests have no audio at all
      if (!kDebugMode) Logs().w('Could not play $asset', e, s);
    }
  }

  static void received() {
    if (AppSettings.gruppechatChatSounds.value) {
      play('assets/sounds/gc_received.wav');
    }
  }

  /// The sound of a message's notification in [room], which the app plays
  /// while it is open (see [gruppechatNotificationChannel]): the chat's own
  /// sound, or the app's usual one. At most one every two seconds, so a
  /// burst of messages doesn't rattle. One kept quiet by the phone's
  /// silent mode doesn't count.
  static Future<void> notification(Room room) async {
    if (AppSettings.gruppechatSoundVolume.value <= 0) return;
    if (await phoneQuiet()) return;
    final now = DateTime.now();
    final last = _lastNotification;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      return;
    }
    _lastNotification = now;
    await _playNow(
      gruppechatChatSound(room)?.asset ?? gruppechatUsualSoundAsset,
    );
  }
}

/// Whether a call is on ([inCall]), or the [voiceMessage] player plays: a
/// player that has played to the end still counts as playing, but isn't.
/// Safari doesn't say when a call uses the page's audio: its audio session
/// still reads 'auto'.
bool gruppechatAudioInUse(AudioPlayer? voiceMessage, {required bool inCall}) =>
    inCall ||
    (voiceMessage != null &&
        voiceMessage.playing &&
        voiceMessage.processingState != ProcessingState.completed);

/// Sets how loud the app's own sounds are, from 0 to 1, in steps of a tenth.
Future<void> gruppechatSetSoundVolume(double volume) => AppSettings
    .gruppechatSoundVolume
    .setItem((volume.clamp(0.0, 1.0) * 10).round() / 10);

/// [volume] as a percentage, for the settings.
String gruppechatSoundVolumeLabel(double volume) =>
    '${(volume * 100).round()} %';

/// The slider for [AppSettings.gruppechatSoundVolume] in the chat settings.
/// Letting go of it plays the usual notification sound at the new volume.
class GruppechatSoundVolumeTile extends StatefulWidget {
  const GruppechatSoundVolumeTile({super.key});

  @override
  State<GruppechatSoundVolumeTile> createState() =>
      _GruppechatSoundVolumeTileState();
}

class _GruppechatSoundVolumeTileState extends State<GruppechatSoundVolumeTile> {
  late double _volume = AppSettings.gruppechatSoundVolume.value;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return ListTile(
      title: Text(l10n.gruppechatSoundVolume),
      trailing: Text(gruppechatSoundVolumeLabel(_volume)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.gruppechatSoundVolumeDescription),
          Slider(
            key: const Key('gruppechat_sound_volume'),
            value: _volume,
            divisions: 10,
            label: gruppechatSoundVolumeLabel(_volume),
            onChanged: (volume) => setState(() => _volume = volume),
            onChangeEnd: (volume) async {
              await gruppechatSetSoundVolume(volume);
              await GruppechatSounds.play(gruppechatUsualSoundAsset);
            },
          ),
        ],
      ),
    );
  }
}

/// Credits, on the app's licences page, the recording the cat sounds are
/// made from (CC BY 4.0, client/scripts/recordings/README.md). Once.
void gruppechatRegisterSoundLicenses() {
  if (_soundLicensesRegistered) return;
  _soundLicensesRegistered = true;
  LicenseRegistry.addLicense(
    () => Stream.value(
      const LicenseEntryWithLineBreaks([
        gruppechatSoundLicensePackage,
      ], gruppechatSoundLicenseText),
    ),
  );
}

var _soundLicensesRegistered = false;

/// The name the cat sounds' credit has on the licences page.
const gruppechatSoundLicensePackage = 'Hanne Chat: kattelyder';

const gruppechatSoundLicenseText =
    'The notification sounds "Mjau" and "Kattunge" and the effect "Katter" '
    'are made from "Weibliche Britisch Kurzhaar will Futter C1277 MIAUEN.wav" '
    'by PantheraLeo1359531, '
    'https://commons.wikimedia.org/wiki/File:Weibliche_Britisch_Kurzhaar_will_Futter_C1277_MIAUEN.wav, '
    'licensed under CC BY 4.0, https://creativecommons.org/licenses/by/4.0/. '
    'Changes: single meows cut out, mixed down to mono, resampled, low-pass '
    'filtered, faded in and out, and some played faster, which makes them '
    'higher.';

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
          GruppechatSounds.play(sound?.asset ?? gruppechatUsualSoundAsset);
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
