import 'vital_baseline_algorithm.dart';
import 'vital_reading.dart';

/// Display-only approximation; original records remain the analysis/PDF input.
class VitalMinuteDisplay {
  VitalMinuteDisplay(this.timestamp, this.readings);
  final DateTime timestamp;
  final List<VitalReading> readings;
  bool get simulated => readings.first.simulated;

  double? median(VitalMetric metric) {
    final values =
        readings.map((r) => r.valueFor(metric)).whereType<double>().toList()
          ..sort();
    if (values.isEmpty) return null;
    final middle = values.length ~/ 2;
    return values.length.isOdd
        ? values[middle]
        : (values[middle - 1] + values[middle]) / 2;
  }

  static List<VitalMinuteDisplay> group(List<VitalReading> readings) {
    final buckets = <(int, bool), List<VitalReading>>{};
    for (final reading in readings) {
      final minute = reading.timestamp.millisecondsSinceEpoch ~/ 60000;
      (buckets[(minute, reading.simulated)] ??= []).add(reading);
    }
    return buckets.entries
        .map(
          (entry) => VitalMinuteDisplay(
            DateTime.fromMillisecondsSinceEpoch(entry.key.$1 * 60000),
            entry.value,
          ),
        )
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }
}
