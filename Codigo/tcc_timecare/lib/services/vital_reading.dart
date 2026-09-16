import 'vital_baseline_algorithm.dart';

/// Shared input contract for summaries, occurrences and daily exports.
/// Raw Firebase records are never modified by this parser.
class VitalReading {
  const VitalReading({
    required this.timestamp,
    this.heartRate,
    this.spo2,
    this.temperature,
    this.simulated = false,
  });
  final DateTime timestamp;
  final double? heartRate, spo2, temperature;
  final bool simulated;

  double? valueFor(VitalMetric metric) => switch (metric) {
    VitalMetric.heartRate => heartRate,
    VitalMetric.spo2 => spo2,
    VitalMetric.temperature => temperature,
  };

  static List<VitalReading> parse(Object? raw, {DateTime? now}) {
    if (raw is! Map) return const [];
    final reference = now ?? DateTime.now();
    final output = <VitalReading>[];
    final seen = <(int, double?, double?, double?, bool)>{};
    for (final entry in raw.entries) {
      if (entry.value is! Map) continue;
      final map = entry.value as Map;
      final timestamp = _date(
        map['timestamp'] ?? map['createdAt'] ?? entry.key,
      );
      if (timestamp == null || timestamp.isAfter(reference)) continue;
      double? pick(List<String> keys) {
        for (final key in keys) {
          final value = map[key];
          if (value == null) continue;
          final number = value is num
              ? value.toDouble()
              : double.tryParse('$value');
          if (number != null && number.isFinite) return number;
        }
        return null;
      }

      final hr = pick([
        'heartRate',
        'heart_rate',
        'bpm',
        'frequencia_cardiaca',
      ]);
      final oxygen = pick(['spo2', 'oxigenacao', 'oxygen']);
      final temp = pick(['temperature', 'temperatura', 'temp']);
      if (hr == null && oxygen == null && temp == null) continue;
      final simulated =
          map['simulated'] == true || map['source'] == 'simulated';
      if (!seen.add((
        timestamp.microsecondsSinceEpoch,
        hr,
        oxygen,
        temp,
        simulated,
      ))) {
        continue;
      }
      output.add(
        VitalReading(
          timestamp: timestamp,
          heartRate: hr,
          spo2: oxygen,
          temperature: temp,
          simulated: simulated,
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
