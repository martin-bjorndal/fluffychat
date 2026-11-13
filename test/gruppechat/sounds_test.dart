// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// The cat sounds, cut from a real recording since 1.1.30
// (scripts/gruppechat_sounds.py, scripts/recordings/), and their credit on
// the licences page; and the slider for how loud the app's own sounds are
// (lib/gruppechat/sounds.dart). How they sound can only be heard on a phone.

import 'dart:io';

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
