// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/gruppechat/clock.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

/// Provides extra functionality for formatting the time.
extension DateTimeExtension on DateTime {
  bool operator <(DateTime other) {
    return millisecondsSinceEpoch < other.millisecondsSinceEpoch;
  }

  bool operator >(DateTime other) {
    return millisecondsSinceEpoch > other.millisecondsSinceEpoch;
  }

  bool operator >=(DateTime other) {
    return millisecondsSinceEpoch >= other.millisecondsSinceEpoch;
  }

  bool operator <=(DateTime other) {
    return millisecondsSinceEpoch <= other.millisecondsSinceEpoch;
  }

  /// Checks if two DateTimes are close enough to belong to the same
  /// environment.
  bool sameEnvironment(DateTime prevTime) =>
      difference(prevTime).abs() < const Duration(minutes: 5) &&
      sameDay(prevTime);

  bool sameDay(DateTime prevTime) =>
      prevTime.year == year && prevTime.month == month && prevTime.day == day;

  /// Returns a simple time String.
  String localizedTimeOfDay(BuildContext context) => timeOfDay(
    this,
    in24Hours: use24HourFormat(context),
    languageCode: Localizations.localeOf(context).languageCode,
  );

  /// Returns [localizedTimeOfDay()] if the ChatTime is today, the name of the week
  /// day if the ChatTime is this week and a date string else.
  String localizedTimeShort(BuildContext context) {
    final now = DateTime.now();

    final sameYear = now.year == year;

    final sameDay = sameYear && now.month == month && now.day == day;

    final sameWeek =
        sameYear &&
        !sameDay &&
        now.millisecondsSinceEpoch - millisecondsSinceEpoch <
            1000 * 60 * 60 * 24 * 7;

    if (sameDay) {
      return localizedTimeOfDay(context);
    } else if (sameWeek) {
      return DateFormat.E(
        Localizations.localeOf(context).languageCode,
      ).format(this);
    } else if (sameYear) {
      return DateFormat.MMMd(
        Localizations.localeOf(context).languageCode,
      ).format(this);
    }
    return DateFormat.yMMMd(
      Localizations.localeOf(context).languageCode,
    ).format(this);
  }

  DateTime get dateOnly => DateTime(year, month, day);

  String localizedDate(BuildContext context) {
    final date = dateOnly;
    final now = DateTime.now().dateOnly;

    final sameYear = now.year == date.year;

    final sameDay = now == date;

    final sameWeek =
        sameYear &&
        !sameDay &&
        now.millisecondsSinceEpoch - millisecondsSinceEpoch <
            1000 * 60 * 60 * 24 * 7;

    if (sameDay) {
      return L10n.of(context).today;
    } else if (now.difference(date).inDays == 1) {
      return L10n.of(context).yesterday;
    } else if (sameWeek) {
      return DateFormat.EEEE(
        Localizations.localeOf(context).languageCode,
      ).format(date);
    } else if (sameYear) {
      return DateFormat.MMMMd(
        Localizations.localeOf(context).languageCode,
      ).format(date);
    }
    return DateFormat.yMMMMd(
      Localizations.localeOf(context).languageCode,
    ).format(date);
  }

  /// If the DateTime is today, this returns [localizedTimeOfDay()], if not it also
  /// shows the date.
  /// TODO: Add localization
  String localizedTime(BuildContext context) {
    final now = DateTime.now();

    final sameYear = now.year == year;

    final sameDay = sameYear && now.month == month && now.day == day;

    if (sameDay) return localizedTimeOfDay(context);
    return L10n.of(context).dateAndTimeOfDay(
      localizedTimeShort(context),
      localizedTimeOfDay(context),
    );
  }

  String localizedDetailedTime(BuildContext context) =>
      L10n.of(context).dateAndTimeOfDay(
        DateFormat.yMMMd(
          Localizations.localeOf(context).languageCode,
        ).format(this),
        timeOfDay(
          this,
          in24Hours: use24HourFormat(context),
          languageCode: Localizations.localeOf(context).languageCode,
          seconds: true,
        ),
      );

  /// Check if time needs to be in 24h format
  bool use24HourFormat(BuildContext context) => use24HourClock(context);
}
