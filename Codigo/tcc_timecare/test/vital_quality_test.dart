import 'package:flutter_test/flutter_test.dart';
import 'package:tcc_timecare/services/vital_baseline_algorithm.dart';
import 'package:tcc_timecare/services/vital_quality.dart';
import 'package:tcc_timecare/services/vital_reading.dart';
import 'package:tcc_timecare/services/vital_report_pdf.dart';

void main() {
  final now = DateTime.utc(2026, 10, 19, 12);
  Map<String, Object?> packet() => {
    'timestamp': now.millisecondsSinceEpoch,
    'source': 'esp32_timecare',
    'quality_contract_version': 1,
    'bpm': 72,
    'spo2': 98,
    'temperatura': 36.5,
    'bpm_status': 'unvalidated_estimate',
    'spo2_status': 'unvalidated_estimate',
    'temperature_status': 'unvalidated_estimate',
    'bpm_summary_count': 5,
    'temperature_samples': 5,
    'temperature_type': 'tmp117_contact_unvalidated',
    'spo2_diagnostics': {'algorithm_valid': true},
    'quality': <String, Object?>{
      'max_available': true,
      'tmp117_available': true,
      'samples': 125,
      'contact_samples': 125,
      'contact_at_end': true,
      'acquisition_errors': 0,
      'fifo_overflows': 0,
      'register_read_failures': 0,
      'beat_buffer_overflows': 0,
      'recovery_pending': false,
      'registers_ok': true,
      'ir_clipped_samples': 0,
      'red_clipped_samples': 0,
      'validated_sqi': false,
    },
  };
  VitalReading parse(Map<String, Object?> p) =>
      VitalReading.parse({'a': p}, now: now).single;

  test(
    'experimental waveform SQI overrides success only for optical values',
    () {
      for (final eligible in [true, false]) {
        final p = packet();
        (p['quality'] as Map)['ppg_sqi'] = {
          'method': 'timecare_waveform_sqi_v1',
          'eligible': eligible,
          'clinically_validated': false,
        };
        final r = parse(p);
        expect(r.heartRate, eligible ? 72 : null);
        expect(r.spo2, eligible ? 98 : null);
        expect(r.temperature, 36.5);
      }
    },
  );
  test('paired algorithm BPM requires its own valid flag', () {
    final p = packet();
    p['bpm_diagnostics'] = {'algorithm_valid': false};
    expect(parse(p).heartRate, isNull);
    expect(parse(p).spo2, 98);
    p['bpm_diagnostics'] = {'algorithm_valid': true};
    expect(parse(p).heartRate, 72);
    p['bpm_diagnostics'] = {'algorithm_valid': 'true'};
    expect(parse(p).heartRate, isNull);
  });

  test('observational SQI preserves display but cannot create occurrences', () {
    final p = packet();
    (p['quality'] as Map)['ppg_sqi'] = {
      'method': 'timecare_waveform_sqi_v1',
      'eligible': false,
      'enforced': false,
    };
    final r = parse(p);
    expect(r.heartRate, 72);
    expect(r.spo2, 98);
    expect(r.hasUnconfirmedSignal, true);
    expect(r.heartRateQuality.allowsOccurrences, false);
    expect(r.temperatureQuality.allowsOccurrences, true);
    expect(
      r.qualityDescription,
      contains('Qualidade experimental não confirmada'),
    );
    (p['quality'] as Map)['acquisition_errors'] = 1;
    expect(parse(p).heartRate, isNull);
    expect(parse(p).spo2, isNull);
  });

  test('malformed waveform SQI never silently becomes eligible', () {
    for (final sqi in [
      null,
      true,
      {},
      {'method': 'unknown', 'eligible': true},
    ]) {
      final p = packet();
      (p['quality'] as Map)['ppg_sqi'] = sqi;
      expect(parse(p).heartRate, isNull);
      expect(parse(p).temperature, 36.5);
    }
  });

  test(
    'high and low values pass technical quality independently of magnitude',
    () {
      for (final bpm in [38, 72, 210]) {
        final reading = parse({
          ...packet(),
          'bpm': bpm,
          'spo2': 82,
          'temperatura': 39.2,
        });
        expect(reading.heartRate, bpm);
        expect(reading.spo2, 82);
        expect(reading.temperature, 39.2);
        expect(reading.heartRateQuality.state, VitalQualityState.usable);
        expect(reading.hasQualityIssue, false);
      }
    },
  );
  for (final fault in <String, Object>{
    'acquisition_errors': 1,
    'fifo_overflows': 1,
    'register_read_failures': 1,
    'recovery_pending': true,
    'registers_ok': false,
    'max_available': false,
    'contact_samples': 0,
    'contact_at_end': false,
    'ir_clipped_samples': 1,
    'samples': 0,
  }.entries) {
    test(
      '${fault.key} excludes optics despite success labels, keeps temperature',
      () {
        final p = packet();
        (p['quality'] as Map)[fault.key] = fault.value;
        final reading = parse(p);
        expect(reading.heartRate, isNull);
        expect(reading.spo2, isNull);
        expect(reading.temperature, 36.5);
        expect(reading.hasQualityIssue, true);
      },
    );
  }
  test(
    'partial contact is inconclusive rather than a low/high measurement',
    () {
      final p = packet();
      (p['quality'] as Map)['contact_samples'] = 100;
      expect(parse(p).heartRateQuality.reason, 'unstable_contact');
      expect(parse(p).spo2, isNull);
    },
  );
  test('red clipping affects only SpO2, beat buffer overflow only BPM', () {
    final p = packet();
    (p['quality'] as Map)['red_clipped_samples'] = 1;
    expect(parse(p).heartRate, 72);
    expect(parse(p).spo2, isNull);
    (p['quality'] as Map)['red_clipped_samples'] = 0;
    (p['quality'] as Map)['beat_buffer_overflows'] = 1;
    expect(parse(p).heartRate, isNull);
    expect(parse(p).spo2, 98);
  });
  test('a temperature failure does not remove BPM or SpO2', () {
    final reading = parse({...packet(), 'temperature_status': 'read_error'});
    expect(reading.temperature, isNull);
    expect(reading.heartRate, 72);
    expect(reading.spo2, 98);
  });
  test('invalid algorithm flag and no new intervals prevent stale values', () {
    final reading = parse({
      ...packet(),
      'bpm_summary_count': 0,
      'spo2_diagnostics': {'algorithm_valid': false},
    });
    expect(reading.heartRate, isNull);
    expect(reading.spo2, isNull);
    expect(reading.temperature, 36.5);
  });
  for (final state in [
    'no_contact',
    'unstable_contact',
    'signal_clipped',
    'no_samples',
    'acquisition_gap',
    'insufficient_data',
    'sensor_unavailable',
    'algorithm_invalid',
    'not_measured',
    'unknown_future_state',
  ]) {
    test('explicit $state cannot be bypassed by numeric aliases', () {
      final p = packet()
        ..remove('bpm')
        ..remove('spo2');
      p.addAll({
        'heartRate': 160,
        'oxygen': 80,
        'bpm_status': state,
        'spo2_status': state,
      });
      expect(parse(p).heartRate, isNull);
      expect(parse(p).spo2, isNull);
    });
  }
  test('modern incomplete contract is inconclusive, legacy is identified', () {
    final p = packet()..remove('bpm_status');
    expect(parse(p).heartRate, isNull);
    final old = parse({'timestamp': now.millisecondsSinceEpoch, 'bpm': 210});
    expect(old.heartRate, 210);
    expect(old.hasUnreportedQuality, true);
    expect(old.qualityDescription, contains('Qualidade não informada'));
    final unsupported = parse({...packet(), 'quality_contract_version': 2});
    expect(unsupported.heartRate, isNull);
  });
  test(
    'legacy global status describes BPM and does not mask independent SpO2',
    () {
      final p = packet()
        ..remove('quality_contract_version')
        ..remove('bpm_status');
      (p['quality'] as Map)['status'] = 'insufficient_data';
      expect(parse(p).heartRate, isNull);
      expect(parse(p).spo2, 98);
      expect(parse(p).temperature, 36.5);
    },
  );
  test('malformed quality never throws or silently becomes usable', () {
    for (final malformed in ['bad', null, 4]) {
      final reading = parse({...packet(), 'quality': malformed});
      expect(reading.heartRate, isNull);
      expect(reading.hasQualityIssue, true);
    }
    final p = packet();
    (p['quality'] as Map)['acquisition_errors'] = 'unknown';
    expect(parse(p).heartRateQuality.state, VitalQualityState.inconclusive);
    expect(parse(p).temperature, 36.5);
  });
  test(
    'invalid representation and sensor range do not become observations',
    () {
      for (final value in [0, -999, double.nan, double.infinity]) {
        expect(parse({...packet(), 'bpm': value}).heartRate, isNull);
        expect(parse({...packet(), 'spo2': value}).spo2, isNull);
      }
      expect(parse({...packet(), 'spo2': 101}).spo2, isNull);
      expect(parse({...packet(), 'temperatura': -999}).temperature, isNull);
      expect(
        parse({...packet(), 'heartRate': 'bad', 'bpm': 72}).heartRate,
        isNull,
      );
    },
  );
  test('all-unavailable window stays visible with reasons, not zeros', () {
    final p = packet()
      ..remove('bpm')
      ..remove('spo2')
      ..remove('temperatura');
    p.addAll({
      'bpm_status': 'no_contact',
      'spo2_status': 'no_contact',
      'temperature_status': 'sensor_unavailable',
    });
    final reading = parse(p);
    expect(reading.heartRate, isNull);
    expect(reading.spo2, isNull);
    expect(reading.temperature, isNull);
    expect(reading.qualityDescription, contains('Sem contato'));
  });
  test('different quality at same timestamp is not deduplicated', () {
    final rows = VitalReading.parse({
      'a': packet(),
      'b': {...packet(), 'bpm_status': 'acquisition_gap'},
    }, now: now);
    expect(rows, hasLength(2));
  });
  test('pipeline excludes failed values and keeps high/low outliers', () {
    final values = [38, 68, 69, 70, 71, 72, 210, 999];
    final input = <String, Object?>{
      for (var i = 0; i < values.length; i++)
        '$i': {
          ...packet(),
          'timestamp': now.subtract(Duration(days: i)).millisecondsSinceEpoch,
          'bpm': values[i],
          if (i == 7) 'bpm_status': 'acquisition_gap',
        },
    };
    final readings = VitalReading.parse(input, now: now);
    final eligible = readings.where((r) => r.heartRate != null).toList();
    expect(eligible, hasLength(7));
    final result =
        const VitalBaselineAnalyzer(
          config: VitalAlgorithmConfig(
            minimumSamples: 5,
            minimumObservationDays: 4,
          ),
        ).analyze(
          VitalMetric.heartRate,
          eligible.map(
            (r) => VitalSample(timestamp: r.timestamp, value: r.heartRate!),
          ),
          now: now,
        );
    expect(result.personalMedian, 70);
    expect(
      result.samples.where((s) => s.isOutlier).map((s) => s.sample.value),
      unorderedEquals([38, 210]),
    );
    final export = VitalReportPdf.readingRows(readings);
    expect(export.last['heartRate'], '-');
    expect(export.last['temperature'], '36.5 C');
    expect(export.last['quality'], contains('Falha durante a coleta'));
    expect(export.first['heartRate'], '38 bpm');
  });
}
