import 'package:flutter_test/flutter_test.dart';
import 'package:tcc_timecare/services/vital_baseline_algorithm.dart';
import 'package:tcc_timecare/services/vital_reading.dart';

void main() {
  final now = DateTime.utc(2026, 9, 16);
  const analyzer = VitalBaselineAnalyzer();
  List<VitalSample> series(int count, {int span = 14}) => List.generate(
    count,
    (i) => VitalSample(
      timestamp: now.subtract(
        Duration(minutes: (span * 1440 * i / (count - 1)).round()),
      ),
      value: 65.0 + i % 11,
    ),
  );

  test('default reference requires count without waiting days', () {
    expect(
      analyzer.analyze(VitalMetric.heartRate, series(19), now: now).isReady,
      false,
    );
    expect(
      analyzer
          .analyze(
            VitalMetric.heartRate,
            List.generate(
              20,
              (i) => VitalSample(
                timestamp: now.subtract(Duration(seconds: i)),
                value: 65.0 + i % 11,
              ),
            ),
            now: now,
          )
          .isReady,
      true,
    );
    expect(
      analyzer.analyze(VitalMetric.heartRate, series(20), now: now).isReady,
      true,
    );
  });
  test('hand calculated median MAD and score share the same reference', () {
    const small = VitalBaselineAnalyzer(
      config: VitalAlgorithmConfig(
        minimumSamples: 5,
        minimumObservationDays: 4,
      ),
    );
    final values = [68.0, 69.0, 70.0, 71.0, 72.0, 150.0];
    final samples = List.generate(
      values.length,
      (i) => VitalSample(
        timestamp: now.subtract(Duration(days: i)),
        value: values[i],
      ),
    );
    final result = small.analyze(VitalMetric.heartRate, samples, now: now);
    expect(result.personalMedian, 70.5);
    expect(result.mad, 1.5);
    expect(result.outlierCount, 1);
    expect(
      result.samples.first.robustZScore,
      closeTo(0.6745 * 79.5 / 1.5, 1e-10),
    );
    expect(result.samples.length, 6);
  });
  test('zero MAD remains explicitly unscorable even with an extreme value', () {
    final samples =
        series(
            20,
          ).map((s) => VitalSample(timestamp: s.timestamp, value: 70)).toList()
          ..add(
            VitalSample(
              timestamp: now.subtract(const Duration(hours: 1)),
              value: 150,
            ),
          );
    final result = analyzer.analyze(VitalMetric.heartRate, samples, now: now);
    expect(result.isReady, true);
    expect(result.canScore, false);
    expect(result.mad, 0);
    expect(result.samples.every((s) => s.robustZScore == null), true);
  });
  test(
    'future, old, nonfinite and exact duplicates do not build a reference',
    () {
      final samples = series(19);
      samples.addAll([
        samples.first,
        VitalSample(timestamp: now.add(const Duration(days: 1)), value: 90),
        VitalSample(
          timestamp: now.subtract(const Duration(days: 31)),
          value: 90,
        ),
        VitalSample(timestamp: now, value: double.nan),
        VitalSample(timestamp: now, value: double.infinity),
      ]);
      final result = analyzer.analyze(VitalMetric.heartRate, samples, now: now);
      expect(result.samples.length, 19);
      expect(result.isReady, false);
    },
  );
  test('window includes the exact cutoff and now', () {
    final result = analyzer.analyze(
      VitalMetric.heartRate,
      series(20, span: 30),
      now: now,
    );
    expect(result.samples.length, 20);
    expect(result.isReady, true);
  });
  test('a positive MAD is not replaced by a parameter-dependent floor', () {
    final input = series(20).map(
      (s) => VitalSample(
        timestamp: s.timestamp,
        value: 36 + (s.value - 65) * .001,
      ),
    );
    final result = analyzer.analyze(VitalMetric.temperature, input, now: now);
    expect(result.canScore, true);
    expect(result.mad, lessThan(.1));
    final sample = result.samples.first;
    expect(
      sample.robustZScore,
      closeTo(
        .6745 * (sample.sample.value - result.personalMedian!) / result.mad!,
        1e-10,
      ),
    );
  });
  test('invalid configurations fail explicitly', () {
    const invalid = VitalBaselineAnalyzer(
      config: VitalAlgorithmConfig(minimumSamples: 1),
    );
    expect(
      () => invalid.analyze(VitalMetric.heartRate, [], now: now),
      throwsArgumentError,
    );
  });
  test('outlier cutoff is strict and symmetric', () {
    const small = VitalAlgorithmConfig(
      minimumSamples: 5,
      minimumObservationDays: 4,
    );
    final input = [-10.0, -1.0, 0.0, 1.0, 10.0].indexed
        .map(
          (entry) => VitalSample(
            timestamp: now.subtract(Duration(days: entry.$1)),
            value: entry.$2,
          ),
        )
        .toList();
    final first = const VitalBaselineAnalyzer(
      config: small,
    ).analyze(VitalMetric.heartRate, input, now: now);
    expect(first.outlierCount, 2);
    final exact = first.samples.first.robustZScore!.abs();
    final boundary = VitalBaselineAnalyzer(
      config: VitalAlgorithmConfig(
        minimumSamples: 5,
        minimumObservationDays: 4,
        robustZThreshold: exact,
      ),
    ).analyze(VitalMetric.heartRate, input, now: now);
    expect(boundary.outlierCount, 0);
  });
  test('parser shares aliases and partial-reading handling', () {
    final result = VitalReading.parse({
      'one': {
        'timestamp': now.millisecondsSinceEpoch,
        'frequencia_cardiaca': '72',
        'oxygen': 98,
        'temp': '36.5',
      },
      'two': {'createdAt': '2026-09-15T12:00:00Z', 'bpm': 'NaN', 'spo2': '97'},
    }, now: now);
    expect(result.length, 2);
    expect(result.first.heartRate, 72);
    expect(result.first.spo2, 98);
    expect(result.first.temperature, 36.5);
    expect(result.last.heartRate, null);
    expect(result.last.spo2, 97);
  });
  test(
    'bad timestamps, future and empty records are excluded without throwing',
    () {
      final result = VitalReading.parse({
        'bad': {'timestamp': 'not a date', 'bpm': 70},
        'huge': {'timestamp': 1e100, 'bpm': 70},
        'nan': {'timestamp': double.nan, 'bpm': 70},
        'future': {
          'timestamp': now.add(const Duration(days: 1)).millisecondsSinceEpoch,
          'bpm': 70,
        },
        'empty': {'timestamp': now.millisecondsSinceEpoch},
      }, now: now);
      expect(result, isEmpty);
      expect(VitalReading.parse(null), isEmpty);
    },
  );
  test('duplicates collapse, simulation provenance stays distinct', () {
    final record = {'timestamp': now.millisecondsSinceEpoch, 'bpm': 70};
    final result = VitalReading.parse({
      'a': record,
      'b': record,
      'c': {...record, 'simulated': true},
    }, now: now);
    expect(result.length, 2);
    expect(result.where((r) => r.simulated).length, 1);
  });
  test('timestamp key is accepted and missing values never become zero', () {
    final result = VitalReading.parse({
      '${now.millisecondsSinceEpoch}': {'temperature': 36.2},
    }, now: now);
    expect(result.single.timestamp.isAtSameMomentAs(now), true);
    expect(result.single.heartRate, null);
  });
}
