import 'package:flutter_test/flutter_test.dart';
import 'package:tcc_timecare/services/vital_occurrence_analyzer.dart';
import 'package:tcc_timecare/services/vital_reading.dart';
import 'package:tcc_timecare/services/vital_quality.dart';

void main() {
  final now = DateTime(2026, 10, 19, 12);
  List<VitalReading> baseline() => List.generate(
    20,
    (i) => VitalReading(
      timestamp: now.subtract(Duration(seconds: 600 - i * 20)),
      heartRate: 69.0 + i % 3,
    ),
  );
  VitalReading point(
    int second,
    double? value, {
    bool simulated = false,
    VitalQuality quality = VitalQuality.unreported,
  }) => VitalReading(
    timestamp: now.subtract(Duration(seconds: 100 - second)),
    heartRate: value,
    simulated: simulated,
    heartRateQuality: quality,
  );
  List<VitalEpisode> analyze(List<VitalReading> tail) =>
      const VitalOccurrenceAnalyzer().analyze([
        ...baseline(),
        ...tail,
      ], now: now);

  test('unconfirmed observational values cannot confirm an episode', () {
    const unconfirmed = VitalQuality(
      VitalQualityState.usable,
      'experimental_sqi_observation',
      occurrenceEligible: false,
    );
    final result = analyze([
      point(0, 160, quality: unconfirmed),
      point(20, 160, quality: unconfirmed),
      point(40, 160, quality: unconfirmed),
    ]);
    expect(result, isEmpty);
  });
  test(
    'single spike remains unconfirmed, sustained high and low group once',
    () {
      expect(analyze([point(0, 160), point(20, 70)]).single.sustained, false);
      for (final value in [160.0, 40.0]) {
        final e = analyze([
          point(0, value),
          point(20, value),
          point(40, value),
        ]).single;
        expect(e.sustained, true);
        expect(e.duration.inSeconds, 40);
        expect(e.samples.length, 3);
      }
    },
  );
  test('rapid repeated packets alone cannot confirm duration', () {
    expect(
      analyze([point(0, 160), point(1, 160), point(2, 160)]).single.sustained,
      false,
    );
  });
  test(
    'missing, failed, recovered, opposite and distant readings break runs',
    () {
      for (final middle in [
        point(20, null),
        point(20, 70),
        point(20, 40),
        point(
          20,
          160,
          quality: const VitalQuality(
            VitalQualityState.inconclusive,
            'acquisition_gap',
          ),
        ),
      ]) {
        expect(
          analyze([
            point(0, 160),
            middle,
            point(40, 160),
          ]).any((e) => e.sustained),
          false,
        );
      }
      expect(
        analyze([
          point(0, 160),
          point(40, 160),
          point(80, 160),
        ]).any((e) => e.sustained),
        false,
      );
    },
  );
  test(
    'simulations, duplicate timestamps and insufficient history cannot confirm',
    () {
      expect(
        analyze([
          point(0, 160),
          point(20, 160, simulated: true),
          point(40, 160),
        ]).any((e) => e.sustained),
        false,
      );
      expect(
        analyze([
          point(0, 160),
          point(0, 160),
          point(20, 160),
        ]).any((e) => e.sustained),
        false,
      );
      expect(
        const VitalOccurrenceAnalyzer().analyze([
          point(0, 160),
          point(20, 160),
          point(40, 160),
        ], now: now),
        isEmpty,
      );
    },
  );
  test('future changes cannot erase a previous persistent episode', () {
    final tail = [point(0, 160), point(20, 160), point(40, 160)];
    final before = analyze(tail).first;
    final after = analyze([...tail, point(60, 160), point(80, 160)]).first;
    expect(before.samples.first.robustZScore, after.samples.first.robustZScore);
    expect(after.sustained, true);
  });
}
