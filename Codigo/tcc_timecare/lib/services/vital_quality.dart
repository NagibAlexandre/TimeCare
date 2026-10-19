import 'vital_baseline_algorithm.dart';

enum VitalQualityState { usable, unavailable, inconclusive, unreported }

/// Acquisition eligibility, independent of clinical ranges and personal history.
class VitalQuality {
  const VitalQuality(this.state, this.reason, {this.occurrenceEligible = true});

  static const unreported = VitalQuality(
    VitalQualityState.unreported,
    'not_reported',
  );
  final VitalQualityState state;
  final String reason;
  final bool occurrenceEligible;
  bool get allowsOccurrences => allowsAnalysis && occurrenceEligible;

  // Legacy records remain readable, with their missing quality made explicit.
  bool get allowsAnalysis =>
      state == VitalQualityState.usable ||
      state == VitalQualityState.unreported;

  String get label => switch (reason) {
    'unvalidated_estimate' => 'Sem falha de aquisição identificada',
    'not_reported' => 'Qualidade não informada',
    'sensor_unavailable' => 'Sensor indisponível',
    'no_contact' => 'Sem contato com o sensor',
    'unstable_contact' => 'Contato instável; repita a medição',
    'signal_clipped' => 'Sinal saturado; reposicione o sensor',
    'acquisition_gap' => 'Falha durante a coleta',
    'insufficient_data' => 'Dados insuficientes; aguarde nova medição',
    'signal_quality_inconclusive' =>
      'Sinal óptico inconclusivo; repita a medição',
    'experimental_sqi_observation' => 'Qualidade experimental não confirmada',
    'algorithm_invalid' => 'Não foi possível calcular a medição',
    'read_error' => 'Falha na leitura do sensor',
    'no_samples' => 'Sem amostras novas',
    'not_measured' => 'Não medido',
    'invalid_value' => 'Valor inválido',
    _ => 'Qualidade inconclusiva',
  };

  static VitalQuality _unavailable(String reason) =>
      VitalQuality(VitalQualityState.unavailable, reason);
  static VitalQuality _inconclusive(String reason) =>
      VitalQuality(VitalQualityState.inconclusive, reason);

  static VitalQuality evaluate(
    Map packet,
    VitalMetric metric,
    double? value, {
    required bool valueProvided,
  }) {
    final version = packet['quality_contract_version'];
    if (packet.containsKey('quality_contract_version') && version != 1) {
      return _inconclusive('unsupported_quality');
    }
    final rawQuality = packet['quality'];
    if (packet.containsKey('quality') && rawQuality is! Map) {
      return _inconclusive('invalid_quality');
    }
    final q = rawQuality is Map ? rawQuality : const {};
    final optical = metric != VitalMetric.temperature;
    final oxygen = metric == VitalMetric.spo2;
    var observationWarning = false;
    if (optical && q.containsKey('ppg_sqi')) {
      final sqi = q['ppg_sqi'];
      if (sqi is! Map ||
          sqi['method'] != 'timecare_waveform_sqi_v1' ||
          sqi['eligible'] is! bool ||
          (sqi.containsKey('enforced') && sqi['enforced'] is! bool)) {
        return _inconclusive('invalid_quality');
      }
      if (sqi['eligible'] != true) {
        if (sqi['enforced'] == false) {
          observationWarning = true;
        } else {
          return _inconclusive('signal_quality_inconclusive');
        }
      }
    }

    // A success label never overrides explicit evidence of acquisition failure.
    final counters = optical
        ? [
            'samples',
            'contact_samples',
            'acquisition_errors',
            'fifo_overflows',
            'register_read_failures',
            'ir_clipped_samples',
            if (oxygen) 'red_clipped_samples' else 'beat_buffer_overflows',
          ]
        : <String>[];
    for (final key in counters) {
      if (q.containsKey(key) &&
          (q[key] is! num || !(q[key] as num).isFinite || q[key] < 0)) {
        return _inconclusive('invalid_quality');
      }
    }
    for (final key
        in optical
            ? [
                'max_available',
                'registers_ok',
                'recovery_pending',
                'contact_at_end',
              ]
            : ['tmp117_available']) {
      if (q.containsKey(key) && q[key] is! bool) {
        return _inconclusive('invalid_quality');
      }
    }
    bool positive(String key) => q[key] is num && q[key] > 0;
    if (optical) {
      if (q['max_available'] == false) {
        return _unavailable('sensor_unavailable');
      }
      if (positive('acquisition_errors') ||
          positive('fifo_overflows') ||
          positive('register_read_failures') ||
          q['recovery_pending'] == true ||
          q['registers_ok'] == false ||
          (!oxygen && positive('beat_buffer_overflows'))) {
        return _inconclusive('acquisition_gap');
      }
      if (positive('ir_clipped_samples') ||
          (oxygen && positive('red_clipped_samples'))) {
        return _inconclusive('signal_clipped');
      }
      if (q['samples'] == 0) return _unavailable('no_samples');
      if (q['contact_samples'] == 0) return _unavailable('no_contact');
      if (q['contact_at_end'] == false ||
          (q['samples'] is num &&
              q['contact_samples'] is num &&
              q['samples'] != q['contact_samples'])) {
        return _inconclusive('unstable_contact');
      }
    } else if (q['tmp117_available'] == false) {
      return _unavailable('sensor_unavailable');
    }

    final statusKey = switch (metric) {
      VitalMetric.heartRate => 'bpm_status',
      VitalMetric.spo2 => 'spo2_status',
      VitalMetric.temperature => 'temperature_status',
    };
    // In older firmware quality.status described BPM, not all three metrics.
    final hasStatus =
        packet.containsKey(statusKey) ||
        (metric == VitalMetric.heartRate && q.containsKey('status'));
    final status = packet.containsKey(statusKey)
        ? packet[statusKey]
        : metric == VitalMetric.heartRate
        ? q['status']
        : null;
    if (hasStatus && status != 'unvalidated_estimate') {
      return switch (status) {
        'sensor_unavailable' ||
        'no_contact' ||
        'no_samples' ||
        'not_measured' ||
        'read_error' ||
        'algorithm_invalid' => _unavailable(status as String),
        'acquisition_gap' ||
        'unstable_contact' ||
        'signal_clipped' ||
        'signal_quality_inconclusive' ||
        'insufficient_data' => _inconclusive(status as String),
        _ => _inconclusive('invalid_quality'),
      };
    }
    if (version == 1 && !packet.containsKey(statusKey)) {
      return _inconclusive('missing_quality');
    }
    if (metric == VitalMetric.heartRate &&
        packet.containsKey('bpm_diagnostics')) {
      final diagnostic = packet['bpm_diagnostics'];
      if (diagnostic is! Map || diagnostic['algorithm_valid'] is! bool) {
        return _inconclusive('invalid_quality');
      }
      if (diagnostic['algorithm_valid'] == false) {
        return _unavailable('algorithm_invalid');
      }
    }
    if (oxygen && packet.containsKey('spo2_diagnostics')) {
      final diagnostic = packet['spo2_diagnostics'];
      if (diagnostic is! Map || diagnostic['algorithm_valid'] is! bool) {
        return _inconclusive('invalid_quality');
      }
      if (diagnostic['algorithm_valid'] == false) {
        return _unavailable('algorithm_invalid');
      }
    }
    final countKey = switch (metric) {
      VitalMetric.heartRate => 'bpm_summary_count',
      VitalMetric.temperature => 'temperature_samples',
      VitalMetric.spo2 => null,
    };
    if (countKey != null && packet.containsKey(countKey)) {
      final count = packet[countKey];
      if (count is! num || !count.isFinite || count < 0) {
        return _inconclusive('invalid_quality');
      }
      if (count == 0) return _inconclusive('insufficient_data');
    }
    if (value == null) {
      return _unavailable(valueProvided ? 'invalid_value' : 'not_measured');
    }
    // Representation limits only: never reject a low/high physiological value.
    if (!value.isFinite ||
        (metric == VitalMetric.heartRate && value <= 0) ||
        (oxygen && (value <= 0 || value > 100)) ||
        (metric == VitalMetric.temperature &&
            packet['temperature_type'] == 'tmp117_contact_unvalidated' &&
            (value < -55 || value > 150))) {
      return _unavailable('invalid_value');
    }
    if (observationWarning) {
      return const VitalQuality(
        VitalQualityState.usable,
        'experimental_sqi_observation',
        occurrenceEligible: false,
      );
    }
    return hasStatus
        ? const VitalQuality(VitalQualityState.usable, 'unvalidated_estimate')
        : unreported;
  }
}
