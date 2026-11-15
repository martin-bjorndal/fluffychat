// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// The time under a message, as the chat shows it on a PC or in a browser,
// where the computer doesn't tell the app how its owner reads the clock.

import 'package:fluffychat/gruppechat/clock.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(initializeDateFormatting);

  // The app's own languages.
  for (final language in const [Locale('nb'), Locale('en')]) {
    testWidgets('a PC with the app in ${language.languageCode} shows 14:05', (
      tester,
    ) async {
      final sent = DateTime(2026, 11, 15, 14, 5, 9);
      late bool in24Hours;
      late String shown;
      late String seconds;
      await tester.pumpWidget(
        Localizations(
          locale: language,
          delegates: const [DefaultWidgetsLocalizations.delegate],
          child: MediaQuery(
            data: const MediaQueryData(alwaysUse24HourFormat: false),
            child: Builder(
              builder: (context) {
                in24Hours = use24HourClock(context);
                shown = sent.localizedTimeOfDay(context);
                seconds = timeOfDay(
                  sent,
                  in24Hours: sent.use24HourFormat(context),
                  languageCode: language.languageCode,
                  seconds: true,
                );
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(in24Hours, isTrue);
      expect(shown, '14:05');
      expect(seconds, '14:05:09');
    });
  }
}
