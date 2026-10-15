// Shared helpers for the day labels the diary/screens render — tests
// recreate the label to key their finders on exactly what the UI shows.
import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// The German header day label exactly as the diary renders it.
///
/// No host-timezone shifting: the screen formats the UTC-midnight dates
/// verbatim, each read by its own fields. The "Heute"-prefix wording is
/// resolved through the real localization bundle, so a wording change
/// breaks the test, not the user.
String germanDayLabel(DateTime day, {DateTime? today}) {
  final date = DateFormat.yMMMEd('de').format(DateOnly.normalize(day));
  final isToday =
      today != null &&
      DateOnly.sameDay(DateOnly.normalize(day), DateOnly.normalize(today));
  return isToday
      ? lookupAppLocalizations(const Locale('de')).todayDate(date)
      : date;
}
