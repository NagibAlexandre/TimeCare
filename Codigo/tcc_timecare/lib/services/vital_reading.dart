import 'vital_baseline_algorithm.dart';
import 'vital_quality.dart';

/// Shared input contract for summaries, occurrences and daily exports.
/// Raw Firebase records are never modified by this parser.
class VitalReading {
  const VitalReading({
    required this.timestamp,
    this.heartRate,
    this.spo2,
    this.temperature,
    this.simulated = false,
    this.heartRateQuality = VitalQuality.unreported,
    this.spo2Quality = VitalQuality.unreported,
    this.temperatureQuality = VitalQuality.unreported,
  });
  final DateTime timestamp;
  final double? heartRate, spo2, temperature;
  final bool simulated;
  final VitalQuality heartRateQuality, spo2Quality, temperatureQuality;

  VitalQuality qualityFor(VitalMetric metric) => switch (metric) {
    VitalMetric.heartRate => heartRateQuality,
    VitalMetric.spo2 => spo2Quality,
    VitalMetric.temperature => temperatureQuality,
  };

  bool get hasQualityIssue => VitalMetric.values.any(
    (metric) =>
        !qualityFor(metric).allowsAnalysis &&
        qualityFor(metric).reason != 'not_measured',
  );

  bool get hasUnreportedQuality => VitalMetric.values.any(
    (metric) =>
        valueFor(metric) != null &&
        qualityFor(metric).state == VitalQualityState.unreported,
  );

  bool get hasUnconfirmedSignal => VitalMetric.values.any(
    (metric) => qualityFor(metric).reason == 'experimental_sqi_observation',
  );

  String get qualityDescription {
    final notes = <String>[];
    for (final metric in VitalMetric.values) {
      final quality = qualityFor(metric);
      if ((quality.allowsAnalysis &&
              quality.reason != 'experimental_sqi_observation') ||
          quality.reason == 'not_measured') {
        continue;
      }
      final name = switch (metric) {
        VitalMetric.heartRate => 'BPM',
        VitalMetric.spo2 => 'SpO2',
        VitalMetric.temperature => 'Temperatura',
      };
      notes.add('$name: ${quality.label}');
    }
    if (hasUnreportedQuality) {
      notes.add('Qualidade não informada');
    }
    if (notes.isEmpty &&
        heartRate == null &&
        spo2 == null &&
        temperature == null) {
      return 'Sem medição disponível';
    }
    return notes.isEmpty
        ? 'Sem falha de aquisição identificada'
        : notes.join('; ');
  }

  double? valueFor(VitalMetric metric) => switch (metric) {
    VitalMetric.heartRate => heartRate,
    VitalMetric.spo2 => spo2,
    VitalMetric.temperature => temperature,
  };

  static List<VitalReading> parse(Object? raw, {DateTime? now}) {
    if (raw is! Map) return const [];
    final reference = now ?? DateTime.now();
    final output = <VitalReading>[];
    final seen =
        <(int, double?, double?, double?, bool, String, String, String)>{};
    for (final entry in raw.entries) {
      if (entry.value is! Map) continue;
      final map = entry.value as Map;
      final timestamp = _date(
        map['timestamp'] ?? map['createdAt'] ?? entry.key,
      );
      if (timestamp == null || timestamp.isAfter(reference)) continue;
      (double?, bool) pick(List<String> keys) {
        for (final key in keys) {
          final value = map[key];
          if (value == null) continue;
          final number = value is num
              ? value.toDouble()
              : double.tryParse('$value');
          // A malformed canonical value cannot be replaced by a stale alias.
          return (number != null && number.isFinite ? number : null, true);
        }
        return (null, false);
      }

      final hr = pick([
        'heartRate',
        'heart_rate',
        'bpm',
        'frequencia_cardiaca',
      ]);
      final oxygen = pick(['spo2', 'oxigenacao', 'oxygen']);
      final temp = pick(['temperature', 'temperatura', 'temp']);
      final hrQuality = VitalQuality.evaluate(
        map,
        VitalMetric.heartRate,
        hr.$1,
        valueProvided: hr.$2,
      );
      final oxygenQuality = VitalQuality.evaluate(
        map,
        VitalMetric.spo2,
        oxygen.$1,
        valueProvided: oxygen.$2,
      );
      final tempQuality = VitalQuality.evaluate(
        map,
        VitalMetric.temperature,
        temp.$1,
        valueProvided: temp.$2,
      );
      final hasQuality =
          map.containsKey('quality') ||
          map.containsKey('quality_contract_version') ||
          map.containsKey('bpm_status') ||
          map.containsKey('spo2_status') ||
          map.containsKey('temperature_status');
      if (!hr.$2 && !oxygen.$2 && !temp.$2 && !hasQuality) continue;
      final acceptedHr = hrQuality.allowsAnalysis ? hr.$1 : null;
      final acceptedOxygen = oxygenQuality.allowsAnalysis ? oxygen.$1 : null;
      final acceptedTemp = tempQuality.allowsAnalysis ? temp.$1 : null;
      final simulated =
          map['simulated'] == true || map['source'] == 'simulated';
      if (!seen.add((
        timestamp.microsecondsSinceEpoch,
        acceptedHr,
        acceptedOxygen,
        acceptedTemp,
        simulated,
        hrQuality.reason,
        oxygenQuality.reason,
        tempQuality.reason,
      ))) {
        continue;
      }
      output.add(
        VitalReading(
          timestamp: timestamp,
          heartRate: acceptedHr,
          spo2: acceptedOxygen,
          temperature: acceptedTemp,
          simulated: simulated,
          heartRateQuality: hrQuality,
          spo2Quality: oxygenQuality,
          temperatureQuality: tempQuality,
        ),
      );
    }
    return output..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  static DateTime? _date(Object? raw) {
    final numeric = raw is num
        ? raw
        : (raw is String ? num.tryParse(raw) : null);
    if (numeric != null) {
      if (!numeric.isFinite || numeric.abs() > 8640000000000000) return null;
      return DateTime.fromMillisecondsSinceEpoch(numeric.toInt());
    }
    return raw is String ? DateTime.tryParse(raw)?.toLocal() : null;
  }
}
