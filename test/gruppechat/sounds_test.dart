// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// The cat sounds, cut from a real recording since 1.1.30
// (scripts/gruppechat_sounds.py, scripts/recordings/), and their credit on
// the licences page; and the slider for how loud the app's own sounds are
// (lib/gruppechat/sounds.dart). How they sound can only be heard on a phone.

import 'dart:io';
import 'dart:math';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/gruppechat/sounds.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A WAV file's channels, sample rate and length in seconds.
(int, int, double) wavFormat(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final channels = data.getUint16(22, Endian.little);
  final rate = data.getUint32(24, Endian.little);
  final bits = data.getUint16(34, Endian.little);
  final size = data.getUint32(40, Endian.little);
  return (channels, rate, size / (rate * channels * bits ~/ 8));
}

/// The 16-bit samples of a mono WAV file written by
/// scripts/gruppechat_sounds.py, from -1 to 1.
List<double> wavSamples(File file) {
  final data = ByteData.sublistView(file.readAsBytesSync());
  final size = data.getUint32(40, Endian.little);
  return [
    for (var i = 44; i < 44 + size; i += 2)
      data.getInt16(i, Endian.little) / 32768,
  ];
}

/// The root mean square of the loudest 0.3 seconds of a sound (all of it,
/// if it is shorter).
double loudestRms(File file) {
  final samples = wavSamples(file);
  final (_, rate, _) = wavFormat(file.readAsBytesSync());
  final window = min(rate * 3 ~/ 10, samples.length);
  var loudest = 0.0;
  for (var start = 0; start + window <= samples.length; start += 1600) {
    loudest = max(loudest, rms(samples.sublist(start, start + window)));
  }
  return loudest;
}

double rms(List<double> samples) =>
    sqrt(samples.fold(0.0, (sum, s) => sum + s * s) / samples.length);

/// How bright a sound is: the RMS of how much it changes from one sample to
/// the next, over its RMS. For a pure tone about 2π times its frequency over
/// the sample rate, so higher for sounds with more of their energy high up.
double brightness(List<double> samples) =>
    rms([
      for (var i = 1; i < samples.length; i++) samples[i] - samples[i - 1],
    ]) /
    rms(samples);

void main() {
  test('the cat sounds are cut from the recording', () {
    final recording = File('scripts/recordings/kortharkatt.wav');
    expect(wavFormat(recording.readAsBytesSync()).$1, 1);
    for (final (file, shortest, longest) in [
      ('gc_mjau', 1.0, 1.5),
      ('gc_kattunge', 1.2, 2.0),
      ('gc_effect_katter', 2.0, 3.5),
    ]) {
      final asset = File('assets/sounds/$file.wav').readAsBytesSync();
      final (channels, rate, seconds) = wavFormat(asset);
      expect((channels, rate), (1, 22050), reason: file);
      // The synthesised meows of 1.1.29 lasted 0.6 to 1.4 seconds
      expect(seconds, inInclusiveRange(shortest, longest), reason: file);
    }
    // Android plays the same notification sounds as the app
    for (final sound in [GruppechatSound.meow, GruppechatSound.kitten]) {
      expect(
        File(
          'android/app/src/main/res/raw/${sound.file}.wav',
        ).readAsBytesSync(),
        File(sound.asset).readAsBytesSync(),
      );
    }
  });

  // "Volumet er også helt ekstremt høyt" (1.1.39): normalised to the same
  // peak as the tones, the meows were about 6 dB louder (A-weighted) than
  // the usual notification sound, and were written at half the level.
  // Measured A-weighted, the bell is within 1 dB of the usual sound
  // (notification.mp3, which can't be read here), so it stands in for it.
  // Plain RMS undersells the meows, so they must stay well below the bell.
  // At half the level they still measured as loud as the usual sound, and
  // were "gjerne lågare" (1.1.40): since then a further 4 dB lower
  // (CAT_LEVEL in scripts/gruppechat_sounds.py), 0.35-0.38 of the bell in
  // plain RMS, where half the level measured 0.56-0.61. Below 0.42, so
  // going even 1 dB back up fails. Low-passed and faded since (also 1.1.40),
  // they are as loud A-weighted, and 0.33-0.38 in plain RMS.
  test('the cat sounds are quieter than the bell', () {
    final bell = loudestRms(File('assets/sounds/gc_bjelle.wav'));
    for (final file in ['gc_mjau', 'gc_kattunge', 'gc_effect_katter']) {
      final cat = loudestRms(File('assets/sounds/$file.wav'));
      expect(cat, lessThan(bell * 0.42), reason: file);
    }
  });

  // "Litt mindre skummel" (1.1.40): the recorded meows swell towards their
  // end, and the kitten stopped while at its loudest (its last 0.2 s at 1.02
  // of its loudest 0.3 s), like a shout; the effect 0.30, the meow 0.20.
  // Since then each meow fades out: 0.08-0.18.
  test('the cat sounds die away instead of stopping loud', () {
    for (final file in ['gc_mjau', 'gc_kattunge', 'gc_effect_katter']) {
      final asset = File('assets/sounds/$file.wav');
      final samples = wavSamples(asset);
      final (_, rate, _) = wavFormat(asset.readAsBytesSync());
      final tail = samples.sublist(samples.length - rate ~/ 5);
      expect(rms(tail), lessThan(loudestRms(asset) * 0.25), reason: file);
    }
  });

  // The kitten was its brightest meow sped up 1.6 times, and shrill: 0.67
  // in [brightness], where the bell is 0.36 and the other cats were 0.36-0.39.
  // Since then the meows are low-passed, and that meow is no longer used:
  // 0.30-0.40, the kitten highest, as it is played faster.
  test('the cat sounds are not much shriller than the bell', () {
    for (final file in ['gc_mjau', 'gc_kattunge', 'gc_effect_katter']) {
      expect(
        brightness(wavSamples(File('assets/sounds/$file.wav'))),
        lessThan(0.45),
        reason: file,
      );
    }
  });

  test('the recording is credited on the licences page', () async {
    gruppechatRegisterSoundLicenses();
    gruppechatRegisterSoundLicenses();
    final credits = await LicenseRegistry.licenses
        .where((l) => l.packages.contains(gruppechatSoundLicensePackage))
        .toList();
    expect(credits, hasLength(1));
    final text = credits.single.paragraphs.map((p) => p.text).join();
    for (final part in [
      'PantheraLeo1359531',
      'https://commons.wikimedia.org/wiki/File:Weibliche_Britisch_Kurzhaar_will_Futter_C1277_MIAUEN.wav',
      'CC BY 4.0',
      'https://creativecommons.org/licenses/by/4.0/',
      'Changes:',
      'low-pass filtered',
    ]) {
      expect(text, contains(part));
    }
  });

  testWidgets('the volume slider saves and plays at the new volume', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init();
    final played = <(String, double)>[];
    GruppechatSounds.onPlay = (asset, volume) => played.add((asset, volume));
    addTearDown(() => GruppechatSounds.onPlay = null);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('nb'),
        // As the app has them, so material_ui speaks Norwegian too
        localizationsDelegates: const [
          ...L10n.localizationsDelegates,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: L10n.supportedLocales,
        home: const Scaffold(body: GruppechatSoundVolumeTile()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Lydvolum'), findsOneWidget);
    expect(find.text('100 %'), findsOneWidget);

    // Down to 30 %: from the right end, 70 % of the way to the left
    final slider = find.byKey(const Key('gruppechat_sound_volume'));
    final box = tester.getRect(slider);
    // The track is inset by the thumb's radius on both sides
    const inset = 24.0;
    final width = box.width - 2 * inset;
    await tester.dragFrom(
      Offset(box.right - inset, box.center.dy),
      Offset(-width * 0.7, 0),
    );
    await tester.pumpAndSettle();
    expect(AppSettings.gruppechatSoundVolume.value, 0.3);
    expect(find.text('30 %'), findsWidgets);
    expect(played, [('assets/sounds/notification.mp3', 0.3)]);
  });

  test('the volume is kept in steps of a tenth, from 0 to 1', () async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init();
    await gruppechatSetSoundVolume(0.34);
    expect(AppSettings.gruppechatSoundVolume.value, 0.3);
    await gruppechatSetSoundVolume(1.7);
    expect(AppSettings.gruppechatSoundVolume.value, 1.0);
    expect(gruppechatSoundVolumeLabel(0.30000000000000004), '30 %');
  });
}
