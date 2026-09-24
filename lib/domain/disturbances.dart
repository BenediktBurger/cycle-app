// The temperature-disturbance letter codes of a tracked day: the paper
// sheet's disturbance codes, derived straight from a [DailyEntry]'s raw
// `tempDisturbances` mask (TempDisturbance vocabulary, models.dart).
//
// Pure Dart, no Flutter import: the cycle chart's disturbance row, its
// help-sheet glossary sample and the PDF export's disturbance strip row
// all render through this one function, so the letter vocabulary cannot
// drift between them. Nothing interprets the letters anywhere — they are
// raw-observation display only (ADR-0001, Mode M).
//
// TODO(user-review): the letter vocabulary mirrors the paper sheet's
// disturbance codes; the experts may want different ones.
import 'models.dart';

/// The letter codes of [day]'s temperature disturbances, one per set
/// disturbance flag, in the render order the disturbance rows stack them:
/// late to bed → "sp", night awakening → "a", alcohol → "alk", illness →
/// "kr" (Reise is not representable in this vocabulary, so it never
/// appears). A null day or a flag-free day yields an empty list.
List<String> disturbanceLetters(DailyEntry? day) => day == null
    ? const []
    : [
        for (final disturbance in TempDisturbance.values)
          if (day.tempDisturbances & disturbance.bit != 0) disturbance.token,
      ];
