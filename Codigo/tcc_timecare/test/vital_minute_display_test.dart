import 'package:flutter_test/flutter_test.dart';
import 'package:tcc_timecare/services/vital_minute_display.dart';
import 'package:tcc_timecare/services/vital_reading.dart';
import 'package:tcc_timecare/services/vital_baseline_algorithm.dart';
import 'package:tcc_timecare/services/vital_report_pdf.dart';

void main() {
  test('minute median preserves gaps, sources and original PDF rows', () {
    final time = DateTime(2026, 10, 19, 12);
    final rows = [
      VitalReading(timestamp: time, heartRate: 60),
      VitalReading(
        timestamp: time.add(const Duration(seconds: 10)),
        heartRate: 80,
      ),
      VitalReading(
        timestamp: time.add(const Duration(seconds: 20)),
        heartRate: 200,
      ),
      VitalReading(timestamp: time, heartRate: 100, simulated: true),
      VitalReading(timestamp: time.add(const Duration(minutes: 2))),
    ];
    final grouped = VitalMinuteDisplay.group(rows);
    expect(grouped.length, 3);
    final first = grouped.singleWhere(
      (g) => g.timestamp == time && !g.simulated,
    );
    expect(first.median(VitalMetric.heartRate), 80);
    expect(first.median(VitalMetric.spo2), isNull);
    expect(VitalReportPdf.readingRows(rows).length, 5);
    expect(rows[2].heartRate, 200);
  });
}
