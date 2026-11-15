// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Whether the app shows times on the 24-hour clock or with AM/PM.

import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter/widgets.dart' show BuildContext, MediaQuery;
import 'package:intl/intl.dart';

/// Where the app runs, as far as the clock is concerned.
enum ClockPlatform { android, other }

/// Whether times show on the 24-hour clock.
///
/// Android tells the app what the phone is set to ([deviceSays24Hours]).
/// Browsers and PCs don't, and iPhones only say so when 24 hours is on; the
/// language of the browser or PC is often English even in Norway. So
/// everywhere but Android the app uses the 24-hour clock, as people do here.
bool showsTimeIn24Hours({
  required ClockPlatform platform,
  required bool deviceSays24Hours,
}) => platform != ClockPlatform.android || deviceSays24Hours;

/// [time] as the app shows it under a message, like "14:05" or "2:05 PM".
String timeOfDay(
  DateTime time, {
  required bool in24Hours,
  required String languageCode,
  bool seconds = false,
}) {
  final pattern = in24Hours
      ? (seconds ? 'HH:mm:ss' : 'HH:mm')
      : (seconds ? 'h:mm:ss a' : 'h:mm a');
  return DateFormat(pattern, languageCode).format(time);
}

/// [showsTimeIn24Hours] for this device.
bool use24HourClock(BuildContext context) => showsTimeIn24Hours(
  platform: PlatformInfos.isAndroid
      ? ClockPlatform.android
      : ClockPlatform.other,
  deviceSays24Hours: MediaQuery.alwaysUse24HourFormatOf(context),
);
