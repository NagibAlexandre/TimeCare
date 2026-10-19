import 'vital_baseline_algorithm.dart';
import 'vital_reading.dart';

class VitalEpisode {
  VitalEpisode(this.metric, this.simulated, this.samples);
  final VitalMetric metric;
  final bool simulated;
  final List<VitalSampleResult> samples;
  DateTime get start => samples.first.sample.timestamp;
  DateTime get end => samples.last.sample.timestamp;
  Duration get duration => end.difference(start);
  bool get sustained =>
      samples.length >= 3 && duration >= const Duration(seconds: 40);
  bool get above => samples.first.robustZScore! > 0;
  String get label => switch (metric) {
    VitalMetric.heartRate => 'Frequência cardíaca',
    VitalMetric.spo2 => 'Oxigenação',
    VitalMetric.temperature => 'Temperatura',
  };
  String get unit => switch (metric) {
    VitalMetric.heartRate => 'bpm',
    VitalMetric.spo2 => '%',
    VitalMetric.temperature => '°C',
  };
  double get extreme => samples
      .map((s) => s.sample.value)
      .reduce((a, b) => above ? (a > b ? a : b) : (a < b ? a : b));
}

/// Experimental persistence screen, not an artifact/clinical diagnosis.
/// PMID 9676861 supports temporal filtering for SpO2; see docs for adaptations.
class VitalOccurrenceAnalyzer {
  const VitalOccurrenceAnalyzer();
  static const maximumGap = Duration(seconds: 30);

  List<VitalEpisode> analyze(List<VitalReading> readings, {DateTime? now}) {
    final episodes = <VitalEpisode>[];
    for (final simulated in [false, true]) {
      final timeline = readings.where((r) => r.simulated == simulated).toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      for (final metric in VitalMetric.values) {
        // Reference uses only earlier technically eligible measurements.
        // Keep a bounded reference and do not teach it detected deviations.
        final history = <VitalSample>[];
        var run = <VitalSampleResult>[];
        void flush() {
          if (run.isNotEmpty) {
            episodes.add(VitalEpisode(metric, simulated, List.of(run)));
          }
          run = [];
        }

        DateTime? previousTime;
        for (final r in timeline) {
          // Conflicting packets at one instant cannot establish persistence.
          if (previousTime == r.timestamp) {
            flush();
            continue;
          }
          previousTime = r.timestamp;
          final value = r.valueFor(metric);
          VitalSampleResult? score;
          final referenceTime = now ?? DateTime.now();
          if (!r.timestamp.isAfter(referenceTime) &&
              !r.timestamp.isBefore(
                referenceTime.subtract(const Duration(days: 30)),
              ) &&
              value != null &&
              r.qualityFor(metric).allowsOccurrences) {
            history.removeWhere(
              (s) => s.timestamp.isBefore(
                r.timestamp.subtract(const Duration(days: 30)),
              ),
            );
            final baseline = const VitalBaselineAnalyzer().analyze(
              metric,
              history,
              now: r.timestamp,
            );
            if (baseline.canScore) {
              final z =
                  0.6745 * (value - baseline.personalMedian!) / baseline.mad!;
              score = VitalSampleResult(
                sample: VitalSample(timestamp: r.timestamp, value: value),
                isOutlier: z.abs() > baseline.config.robustZThreshold,
                robustZScore: z,
              );
            }
            if (score == null || !score.isOutlier) {
              history.add(VitalSample(timestamp: r.timestamp, value: value));
              if (history.length > 200) history.removeAt(0);
            }
          }
          if (score == null || !score.isOutlier) {
            flush();
            continue;
          }
          if (run.isNotEmpty &&
              (r.timestamp.difference(run.last.sample.timestamp) > maximumGap ||
                  (score.robustZScore! > 0) != (run.last.robustZScore! > 0))) {
            flush();
          }
          run.add(score);
        }
        flush();
      }
    }
    return episodes..sort((a, b) => b.start.compareTo(a.start));
  }
}
