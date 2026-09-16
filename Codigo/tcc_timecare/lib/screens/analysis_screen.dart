import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:tcc_timecare/services/realtime_database_rest.dart';
import 'package:tcc_timecare/services/vital_baseline_algorithm.dart';
import 'package:tcc_timecare/services/vital_report_pdf.dart';
import 'package:tcc_timecare/services/vital_reading.dart';

/// Displays the readings published by the ESP32 under
/// `user_test/sinais_vitais`. Both a list keyed by timestamp and a map of
/// readings are supported, so older firmware does not break the application.
class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  final _database = RealtimeDatabaseRest.instance;
  late Future<Object?> _vitalsFuture;
  List<VitalReading> _latestReadings = const [];
  int _days = 7;

  @override
  void initState() {
    super.initState();
    _vitalsFuture = _database.get('user_test/sinais_vitais');
  }

  Future<void> _refresh() async {
    setState(() {
      _vitalsFuture = _database.get('user_test/sinais_vitais');
    });
    await _vitalsFuture;
  }

  Future<void> _exportPdf(List<VitalReading> readings) async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDate: DateTime.now(),
    );
    if (selected == null || !mounted) return;
    final selectedReadings = readings
        .where(
          (item) =>
              item.timestamp.year == selected.year &&
              item.timestamp.month == selected.month &&
              item.timestamp.day == selected.day,
        )
        .toList();
    if (selectedReadings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não há medições nessa data.')),
      );
      return;
    }
    try {
      final rawProfile = await _database.get('user_test');
      final profile = rawProfile is Map
          ? Map<Object?, Object?>.from(rawProfile)
          : <Object?, Object?>{};
      final data = selectedReadings
          .map(
            (item) => <String, Object?>{
              'time': DateFormat('HH:mm').format(item.timestamp),
              'source': item.simulated
                  ? 'Simulada'
                  : 'Não sinalizada como simulada',
              'heartRate': item.heartRate == null
                  ? '-'
                  : '${item.heartRate!.round()} bpm',
              'spo2': item.spo2 == null ? '-' : '${item.spo2!.round()}%',
              'temperature': item.temperature == null
                  ? '-'
                  : '${item.temperature!.toStringAsFixed(1)} C',
            },
          )
          .toList();
      final bytes = await VitalReportPdf.build(
        profile: profile,
        date: selected,
        readings: data,
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'timecare-${DateFormat('yyyy-MM-dd').format(selected)}.pdf',
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível gerar o PDF.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Sinais vitais'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Gerar recibo em PDF',
            onPressed: () => _exportPdf(_latestReadings),
          ),
        ],
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        elevation: 0,
      ),
      body: FutureBuilder<Object?>(
        future: _vitalsFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ErrorState(error: snapshot.error.toString());
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = VitalReading.parse(snapshot.data);
          _latestReadings = all;
          final limit = DateTime.now().subtract(Duration(days: _days));
          final readings = all
              .where((item) => item.timestamp.isAfter(limit))
              .toList();
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _Header(readings: readings),
                const SizedBox(height: 16),
                _PeriodPicker(
                  days: _days,
                  onChanged: (days) => setState(() => _days = days),
                ),
                const SizedBox(height: 16),
                _Summary(readings: readings, baselineReadings: all),
                const SizedBox(height: 20),
                Text(
                  'Medições recentes',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (readings.isEmpty)
                  const _EmptyState()
                else
                  ...readings
                      .take(30)
                      .map(
                        (reading) => _ReadingCard(
                          reading: reading,
                          isOutlier: _isOutlier(reading, all),
                        ),
                      ),
              ],
            ),
          );
        },
      ),
    );
  }

  bool _isOutlier(VitalReading reading, List<VitalReading> all) {
    final analyzer = const VitalBaselineAnalyzer();
    final checks = <(VitalMetric, double?)>[
      (VitalMetric.heartRate, reading.heartRate),
      (VitalMetric.spo2, reading.spo2),
      (VitalMetric.temperature, reading.temperature),
    ];
    for (final check in checks) {
      if (check.$2 == null) continue;
      final result = analyzer.analyze(
        check.$1,
        _samples(
          all.where((item) => item.simulated == reading.simulated).toList(),
          check.$1,
        ),
      );
      if (result.samples.any(
        (sample) =>
            sample.sample.timestamp == reading.timestamp &&
            sample.sample.value == check.$2 &&
            sample.isOutlier,
      )) {
        return true;
      }
    }
    return false;
  }

  List<VitalSample> _samples(List<VitalReading> readings, VitalMetric metric) =>
      readings
          .map(
            (reading) => switch (metric) {
              VitalMetric.heartRate => reading.heartRate,
              VitalMetric.spo2 => reading.spo2,
              VitalMetric.temperature => reading.temperature,
            },
          )
          .indexed
          .where((entry) => entry.$2 != null)
          .map(
            (entry) => VitalSample(
              timestamp: readings[entry.$1].timestamp,
              value: entry.$2!,
            ),
          )
          .toList();
}

class _Header extends StatelessWidget {
  const _Header({required this.readings});
  final List<VitalReading> readings;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark ? scheme.surfaceContainerHighest : scheme.primary;
    final foreground = isDark ? scheme.onSurface : scheme.onPrimary;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.monitor_heart_outlined, color: foreground, size: 32),
          const SizedBox(height: 10),
          Text(
            'Resumo de saúde',
            style: TextStyle(
              color: foreground,
              fontSize: 21,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${readings.length} registros no período; ${readings.where((r) => r.simulated).length} sinalizados como simulados. Análise estatística experimental, sem diagnóstico.',
            style: TextStyle(color: foreground.withValues(alpha: .75)),
          ),
        ],
      ),
    );
  }
}

class _PeriodPicker extends StatelessWidget {
  const _PeriodPicker({required this.days, required this.onChanged});
  final int days;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    children: [1, 7, 30]
        .map(
          (value) => ChoiceChip(
            label: Text(value == 1 ? '24 horas' : '$value dias'),
            selected: days == value,
            onSelected: (_) => onChanged(value),
          ),
        )
        .toList(),
  );
}

class _Summary extends StatelessWidget {
  const _Summary({required this.readings, required this.baselineReadings});
  final List<VitalReading> readings;
  final List<VitalReading> baselineReadings;
  double? _average(double? Function(VitalReading item) pick) {
    final selected = readings.where(
      (r) => r.simulated == !baselineReadings.any((r) => !r.simulated),
    );
    final values = selected.map(pick).whereType<double>().toList();
    return values.isEmpty
        ? null
        : values.reduce((a, b) => a + b) / values.length;
  }

  @override
  Widget build(BuildContext context) {
    final analyzer = const VitalBaselineAnalyzer();
    VitalBaselineResult baseline(
      VitalMetric metric,
      double? Function(VitalReading) pick,
    ) => analyzer.analyze(
      metric,
      baselineReadings
          .where(
            (reading) =>
                pick(reading) != null &&
                reading.simulated == !baselineReadings.any((r) => !r.simulated),
          )
          .map(
            (reading) => VitalSample(
              timestamp: reading.timestamp,
              value: pick(reading)!,
            ),
          ),
    );
    final items = [
      _Metric(
        'Frequência',
        _average((r) => r.heartRate),
        'bpm',
        Icons.favorite_outline,
        Colors.red,
        baseline(VitalMetric.heartRate, (r) => r.heartRate),
      ),
      _Metric(
        'Oxigenação',
        _average((r) => r.spo2),
        '%',
        Icons.air,
        Colors.blue,
        baseline(VitalMetric.spo2, (r) => r.spo2),
      ),
      _Metric(
        'Temperatura',
        _average((r) => r.temperature),
        '°C',
        Icons.thermostat_outlined,
        Colors.orange,
        baseline(VitalMetric.temperature, (r) => r.temperature),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          baselineReadings.any((r) => !r.simulated)
              ? "Resumo e referência: registros não sinalizados como simulados."
              : "Resumo e referência: dados simulados para teste.",
        ),
        const SizedBox(height: 8),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          childAspectRatio: 0.85,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          children: items
              .map(
                (item) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(item.icon, color: item.color),
                        const Spacer(),
                        Text(
                          item.label,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          item.value == null
                              ? 'Sem dados'
                              : 'Média: ${item.value!.toStringAsFixed(1)} ${item.unit}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          item.baseline.isReady
                              ? 'Mediana: ${item.baseline.personalMedian!.toStringAsFixed(1)} ${item.unit}${item.baseline.canScore ? '' : ' (MAD zero; sem escore)'}'
                              : 'Calibrando: ${item.baseline.samples.length}/${item.baseline.config.minimumSamples}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _Metric {
  const _Metric(
    this.label,
    this.value,
    this.unit,
    this.icon,
    this.color,
    this.baseline,
  );
  final String label, unit;
  final double? value;
  final IconData icon;
  final Color color;
  final VitalBaselineResult baseline;
}

class _ReadingCard extends StatelessWidget {
  const _ReadingCard({required this.reading, required this.isOutlier});
  final VitalReading reading;
  final bool isOutlier;
  @override
  Widget build(BuildContext context) {
    final metrics = <String>[];
    if (reading.heartRate != null) {
      metrics.add('${reading.heartRate!.round()} bpm');
    }
    if (reading.spo2 != null) {
      metrics.add('${reading.spo2!.toStringAsFixed(0)}% SpO₂');
    }
    if (reading.temperature != null) {
      metrics.add('${reading.temperature!.toStringAsFixed(1)} °C');
    }
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.monitor_heart_outlined)),
        title: Text(
          metrics.isEmpty
              ? 'Leitura sem métricas reconhecidas'
              : metrics.join(' • '),
        ),
        subtitle: Text(
          '${DateFormat("dd/MM/yyyy 'às' HH:mm").format(reading.timestamp)}${reading.simulated ? ' • SIMULADA' : ''}${isOutlier ? ' • Variação pessoal incomum' : ''}',
        ),
        trailing: isOutlier
            ? const Icon(Icons.info_outline, color: Colors.orange)
            : null,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 48),
    child: Center(
      child: Column(
        children: [
          Icon(Icons.sensors_off_outlined, size: 48, color: Colors.grey),
          SizedBox(height: 12),
          Text('Nenhuma medição encontrada neste período.'),
        ],
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});
  final String error;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        'Não foi possível carregar os sinais vitais.\n$error',
        textAlign: TextAlign.center,
      ),
    ),
  );
}
