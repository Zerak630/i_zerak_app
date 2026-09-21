import 'dart:convert';

import 'package:i_zerak_app/models/commute_dao.dart';

/// Le fichier ne ressemble pas a un export de la Chronologie Google Maps.
class TimelineFormatException implements Exception {
  const TimelineFormatException(this.message);
  final String message;

  @override
  String toString() => 'TimelineFormatException: $message';
}

/// Une journee ou la Chronologie a detecte du velo.
class TimelineBikeDay {
  const TimelineBikeDay({
    required this.date,
    required this.km,
    required this.legs,
    required this.commute,
  });

  final DateTime date;

  /// Distance roulee ce jour-la, tous trajets a velo confondus.
  final double km;

  /// Nombre de trajets a velo.
  final int legs;

  /// Au moins un trajet a velo relie le domicile et le travail, tels que
  /// Google les a reconnus.
  final bool commute;
}

/// Extrait les journees a velo d'un export de la Chronologie Google Maps.
///
/// Lit l'export fait depuis le telephone (Parametres › Localisation ›
/// Chronologie › Exporter), sous ses deux formes connues : l'objet Android a
/// `semanticSegments`, et la liste a plat de l'export iOS, ou les types sont en
/// minuscules et les distances parfois en chaines.
///
/// Un trajet compte comme domicile-travail quand la visite qui le precede et
/// celle qui le suit sont, dans un sens ou dans l'autre, le domicile et le
/// travail. Les autres activites entre deux visites sont sautees : Google
/// coupe parfois un trajet en plusieurs segments.
///
/// Seules les dates, distances et natures de lieux sont retenues ; aucune
/// position ne sort de cette fonction.
List<TimelineBikeDay> parseTimelineBikeDays(String source) {
  final Object? data;
  try {
    data = json.decode(source);
  } on FormatException {
    throw const TimelineFormatException('JSON illisible');
  }

  final List<dynamic> segments;
  if (data is Map && data['semanticSegments'] is List) {
    segments = data['semanticSegments'] as List;
  } else if (data is List) {
    segments = data;
  } else {
    throw const TimelineFormatException('ni semanticSegments, ni liste de segments');
  }

  // Visites et activites seulement, dans l'ordre chronologique : les traces
  // brutes (`timelinePath`) n'apportent rien ici.
  final items = <({DateTime start, String day, Map<dynamic, dynamic> segment})>[];
  for (final segment in segments) {
    if (segment is! Map || (segment['visit'] is! Map && segment['activity'] is! Map)) {
      continue;
    }
    final raw = segment['startTime'];
    final start = raw is String ? DateTime.tryParse(raw) : null;
    if (start == null || raw is! String || raw.length < 10) {
      continue;
    }
    // La date locale est celle ecrite dans l'horodatage, qui porte deja le
    // decalage horaire : convertir en UTC ferait glisser les trajets de nuit
    // sur la veille.
    items.add((start: start, day: raw.substring(0, 10), segment: segment));
  }
  items.sort((a, b) => a.start.compareTo(b.start));

  String? place(Map<dynamic, dynamic> segment) {
    final visit = segment['visit'];
    final candidate = visit is Map ? visit['topCandidate'] : null;
    final type = candidate is Map ? candidate['semanticType'] : null;
    return type is String ? type.toUpperCase() : null;
  }

  String? visitBefore(int index) {
    for (var j = index - 1; j >= 0; j--) {
      if (items[j].segment['visit'] is Map) {
        return place(items[j].segment);
      }
    }
    return null;
  }

  String? visitAfter(int index) {
    for (var j = index + 1; j < items.length; j++) {
      if (items[j].segment['visit'] is Map) {
        return place(items[j].segment);
      }
    }
    return null;
  }

  final km = <String, double>{};
  final legs = <String, int>{};
  final commutes = <String>{};
  for (var i = 0; i < items.length; i++) {
    final activity = items[i].segment['activity'];
    if (activity is! Map) {
      continue;
    }
    final candidate = activity['topCandidate'];
    final type = candidate is Map ? candidate['type'] : null;
    if (type is! String || type.toUpperCase() != 'CYCLING') {
      continue;
    }
    final day = items[i].day;
    km[day] = (km[day] ?? 0) + _metres(activity['distanceMeters']) / 1000;
    legs[day] = (legs[day] ?? 0) + 1;
    final ends = {visitBefore(i), visitAfter(i)};
    if (ends.contains('HOME') && ends.contains('WORK')) {
      commutes.add(day);
    }
  }

  return [
    for (final day in km.keys)
      if (parseDayKey(day) case final DateTime date)
        TimelineBikeDay(
          date: date,
          km: km[day]!,
          legs: legs[day]!,
          commute: commutes.contains(day),
        ),
  ]..sort((a, b) => b.date.compareTo(a.date));
}

double _metres(Object? raw) => switch (raw) {
      num value => value.toDouble(),
      String value => double.tryParse(value) ?? 0,
      _ => 0,
    };
