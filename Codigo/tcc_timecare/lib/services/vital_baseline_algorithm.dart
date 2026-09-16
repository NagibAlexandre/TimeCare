/// Pure, testable vital-sign baseline and outlier analysis.
///
/// All experimental parameters live in [VitalAlgorithmConfig]. The UI and
/// Firebase layers should only consume the returned results.
enum VitalMetric { heartRate, spo2, temperature }

class VitalAlgorithmConfig {
  const VitalAlgorithmConfig({
    this.minimumSamples = 20,
    this.minimumObservationDays = 14,
    this.baselineWindowDays = 30,
    this.robustZThreshold = 3.5,
    this.algorithmVersion = 'baseline-mad-v2',
  });

  final int minimumSamples;
  final int minimumObservationDays;
  final int baselineWindowDays;
  final double robustZThreshold;
  final String algorithmVersion;

  // Observation requirements are experimental, not clinical cutoffs.
  // Formula and statistical threshold: PMID 37749212 (2023), not a
  // validation of wearable vital-sign alerts. See docs/algoritmo_sinais_vitais.md.
}

const defaultVitalAlgorithmConfig = VitalAlgorithmConfig();

class VitalSample {
  const VitalSample({required this.timestamp, required this.value});
  final DateTime timestamp;
  final double value;
}

class VitalSampleResult {
  const VitalSampleResult({
    required this.sample,
    required this.isOutlier,
    this.robustZScore,
  });
  final VitalSample sample;
  final bool isOutlier;
  final double? robustZScore;
}

class VitalBaselineResult {
  const VitalBaselineResult({
    required this.config,
    required this.metric,
    required this.samples,
    required this.isReady,
    this.personalMedian,
    this.mad,
  });
  final VitalAlgorithmConfig config;
  final VitalMetric metric;
  final List<VitalSampleResult> samples;
  final bool isReady;
  final double? personalMedian;
  final double? mad;
  bool get canScore => isReady && mad != null && mad! > 0;
  int get outlierCount => samples.where((sample) => sample.isOutlier).length;
}

class VitalBaselineAnalyzer {
  const VitalBaselineAnalyzer({this.config = defaultVitalAlgorithmConfig});
  final VitalAlgorithmConfig config;

  VitalBaselineResult analyze(
    VitalMetric metric,
    Iterable<VitalSample> input, {
    DateTime? now,
  }) {
    final referenceTime = now ?? DateTime.now();
    if (config.minimumSamples < 2 ||
        config.minimumObservationDays < 0 ||
        config.baselineWindowDays < config.minimumObservationDays ||
        config.baselineWindowDays <= 0 ||
        !config.robustZThreshold.isFinite ||
        config.robustZThreshold <= 0) {
      throw ArgumentError('Invalid experimental baseline configuration');
    }
    final cutoff = referenceTime.subtract(
      Duration(days: config.baselineWindowDays),
    );
    final seen = <(int, double)>{};
    final samples =
        input
            .where(
              (sample) =>
                  sample.value.isFinite &&
                  !sample.timestamp.isBefore(cutoff) &&
                  !sample.timestamp.isAfter(referenceTime) &&
                  seen.add((
                    sample.timestamp.microsecondsSinceEpoch,
                    sample.value,
                  )),
            )
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final observedLongEnough =
        samples.length > 1 &&
        samples.last.timestamp.difference(samples.first.timestamp).inDays >=
            config.minimumObservationDays;
    if (samples.length < config.minimumSamples || !observedLongEnough) {
      return VitalBaselineResult(
        config: config,
        metric: metric,
        samples: samples
            .map(
              (sample) => VitalSampleResult(sample: sample, isOutlier: false),
            )
            .toList(),
        isReady: false,
      );
    }

    final initialMedian = _median(samples.map((sample) => sample.value));
    final initialMad = _median(
      samples.map((sample) => (sample.value - initialMedian).abs()),
    );
    // A degenerate distribution has no defined modified z score. Do not
    // invent a sensor-specific denominator or silently label it normal.
    if (initialMad == 0) {
      return VitalBaselineResult(
        config: config,
        metric: metric,
        samples: samples
            .map(
              (sample) => VitalSampleResult(sample: sample, isOutlier: false),
            )
            .toList(),
        isReady: true,
        personalMedian: initialMedian,
        mad: initialMad,
      );
    }
    final provisional = samples.map((sample) {
      final z = 0.6745 * ((sample.value - initialMedian) / initialMad);
      return VitalSampleResult(
        sample: sample,
        isOutlier: z.abs() > config.robustZThreshold,
        robustZScore: z,
      );
    }).toList();
    // Preserve both observations and the reference actually used for scoring.
    // A statistical deviation is not evidence of a measurement artifact.
    return VitalBaselineResult(
      config: config,
      metric: metric,
      samples: provisional,
      isReady: true,
      personalMedian: initialMedian,
      mad: initialMad,
    );
  }

  double _median(Iterable<double> input) {
    final values = input.toList()..sort();
    final middle = values.length ~/ 2;
    return values.length.isOdd
        ? values[middle]
        : (values[middle - 1] + values[middle]) / 2;
  }
}
