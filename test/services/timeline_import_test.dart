import 'dart:convert';

import 'package:i_zerak_app/services/timeline_import.dart';
import 'package:test/test.dart';

Map<String, dynamic> _visit(String start, String end, String type) => {
      'startTime': start,
      'endTime': end,
      'visit': {
        'topCandidate': {
          'semanticType': type,
          'placeLocation': {'latLng': '47.0°, -0.1°'},
        },
      },
    };

Map<String, dynamic> _move(String start, String end, String type, double metres) => {
      'startTime': start,
      'endTime': end,
      'activity': {
        'distanceMeters': metres,
        'topCandidate': {'type': type, 'probability': 0.9},
      },
    };

String _android(List<Map<String, dynamic>> segments) => json.encode({
      'semanticSegments': [
        ...segments,
        // Trace brute, sans interet ici.
        {
          'startTime': '2026-09-14T00:00:00.000+02:00',
          'endTime': '2026-09-14T02:00:00.000+02:00',
          'timelinePath': [
            {'point': '47.0°, -0.1°', 'time': '2026-09-14T00:10:00.000+02:00'},
          ],
        },
      ],
      'rawSignals': [],
    });

void main() {
  test('aller et retour domicile-travail a velo', () {
    final days = parseTimelineBikeDays(_android([
      _visit('2026-09-14T06:00:00.000+02:00', '2026-09-14T08:00:00.000+02:00', 'HOME'),
      _move('2026-09-14T08:00:00.000+02:00', '2026-09-14T08:25:00.000+02:00', 'CYCLING', 6900),
      _visit('2026-09-14T08:25:00.000+02:00', '2026-09-14T17:30:00.000+02:00', 'WORK'),
      _move('2026-09-14T17:30:00.000+02:00', '2026-09-14T17:58:00.000+02:00', 'CYCLING', 7100),
      _visit('2026-09-14T17:58:00.000+02:00', '2026-09-14T23:59:00.000+02:00', 'HOME'),
    ]));

    expect(days.single.date, DateTime(2026, 9, 14));
    expect(days.single.commute, isTrue);
    expect(days.single.legs, 2);
    expect(days.single.km, closeTo(14.0, 0.001));
  });

  test('un trajet coupe en plusieurs segments reste un domicile-travail', () {
    // Google intercale parfois un bout de marche au milieu du trajet.
    final days = parseTimelineBikeDays(_android([
      _visit('2026-09-15T06:00:00.000+02:00', '2026-09-15T08:00:00.000+02:00', 'HOME'),
      _move('2026-09-15T08:00:00.000+02:00', '2026-09-15T08:10:00.000+02:00', 'CYCLING', 3000),
      _move('2026-09-15T08:10:00.000+02:00', '2026-09-15T08:12:00.000+02:00', 'WALKING', 150),
      _move('2026-09-15T08:12:00.000+02:00', '2026-09-15T08:25:00.000+02:00', 'CYCLING', 3900),
      _visit('2026-09-15T08:25:00.000+02:00', '2026-09-15T17:00:00.000+02:00', 'WORK'),
    ]));

    expect(days.single.commute, isTrue);
    expect(days.single.legs, 2);
  });

  test('une sortie a velo qui ne relie pas domicile et travail est gardee, non cochee', () {
    final days = parseTimelineBikeDays(_android([
      _visit('2026-09-19T09:00:00.000+02:00', '2026-09-19T10:00:00.000+02:00', 'HOME'),
      _move('2026-09-19T10:00:00.000+02:00', '2026-09-19T12:00:00.000+02:00', 'CYCLING', 42000),
      _visit('2026-09-19T12:00:00.000+02:00', '2026-09-19T13:00:00.000+02:00', 'UNKNOWN'),
    ]));

    expect(days.single.commute, isFalse);
    expect(days.single.km, closeTo(42, 0.001));
  });

  test('la voiture ne compte pas', () {
    final days = parseTimelineBikeDays(_android([
      _visit('2026-09-16T06:00:00.000+02:00', '2026-09-16T08:00:00.000+02:00', 'HOME'),
      _move('2026-09-16T08:00:00.000+02:00', '2026-09-16T08:15:00.000+02:00', 'IN_PASSENGER_VEHICLE', 7000),
      _visit('2026-09-16T08:15:00.000+02:00', '2026-09-16T17:00:00.000+02:00', 'WORK'),
    ]));

    expect(days, isEmpty);
  });

  test('la date est celle de l horodatage local, pas celle en UTC', () {
    // 00h30 heure d'ete le 17 = 22h30 UTC le 16.
    final days = parseTimelineBikeDays(_android([
      _move('2026-09-17T00:30:00.000+02:00', '2026-09-17T00:50:00.000+02:00', 'CYCLING', 5000),
    ]));

    expect(days.single.date, DateTime(2026, 9, 17));
  });

  test('export iOS : liste a plat, types en minuscules, distances en chaines', () {
    final days = parseTimelineBikeDays(json.encode([
      _visit('2026-09-14T06:00:00.000+02:00', '2026-09-14T08:00:00.000+02:00', 'Home'),
      {
        'startTime': '2026-09-14T08:00:00.000+02:00',
        'endTime': '2026-09-14T08:25:00.000+02:00',
        'activity': {
          'distanceMeters': '6900.0',
          'topCandidate': {'type': 'cycling', 'probability': '0.9'},
        },
      },
      _visit('2026-09-14T08:25:00.000+02:00', '2026-09-14T17:30:00.000+02:00', 'Work'),
    ]));

    expect(days.single.commute, isTrue);
    expect(days.single.km, closeTo(6.9, 0.001));
  });

  test('les jours sortent du plus recent au plus ancien', () {
    final days = parseTimelineBikeDays(_android([
      _move('2026-09-01T08:00:00.000+02:00', '2026-09-01T08:20:00.000+02:00', 'CYCLING', 5000),
      _move('2026-09-10T08:00:00.000+02:00', '2026-09-10T08:20:00.000+02:00', 'CYCLING', 5000),
    ]));

    expect(days.map((d) => d.date.day), [10, 1]);
  });

  test('un fichier qui n est pas une Chronologie est refuse', () {
    expect(() => parseTimelineBikeDays('pas du json'), throwsA(isA<TimelineFormatException>()));
    expect(() => parseTimelineBikeDays('{"autre": 1}'), throwsA(isA<TimelineFormatException>()));
  });
}
