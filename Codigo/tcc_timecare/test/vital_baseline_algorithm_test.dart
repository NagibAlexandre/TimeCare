import 'package:flutter_test/flutter_test.dart';
import 'package:tcc_timecare/services/vital_baseline_algorithm.dart';

void main() {
  const config = VitalAlgorithmConfig(
    minimumSamples: 5,
    minimumObservationDays: 4,
    baselineWindowDays: 30,
    robustZThreshold: 3.5,
  );
  final analyzer = VitalBaselineAnalyzer(config: config);
  final start = DateTime.utc(2026, 1, 1);

  test('does not create a baseline before enough distributed samples', () {
    final result = analyzer.analyze(VitalMetric.heartRate, [
      VitalSample(timestamp: start, value: 70),
    ], now: start.add(const Duration(days: 5)));
    expect(result.isReady, isFalse);
  });

  test('marks an extreme reading while preserving the scoring reference', () {
    final samples =
        List.generate(
          5,
          (index) => VitalSample(
            timestamp: start.add(Duration(days: index)),
            value: 68.0 + index,
          ),
        ).toList()..add(
          VitalSample(
            timestamp: start.add(const Duration(days: 5)),
            value: 150,
          ),
        );
    final result = analyzer.analyze(
      VitalMetric.heartRate,
      samples,
      now: start.add(const Duration(days: 5)),
    );
    expect(result.isReady, isTrue);
    expect(result.outlierCount, 1);
    expect(result.personalMedian, closeTo(70.5, 0.01));
    expect(result.mad, closeTo(1.5, 0.01));
  });
}
