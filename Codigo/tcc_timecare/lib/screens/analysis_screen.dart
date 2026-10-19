import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:tcc_timecare/services/realtime_database_rest.dart';
import 'package:tcc_timecare/services/vital_baseline_algorithm.dart';
import 'package:tcc_timecare/services/vital_report_pdf.dart';
import 'package:tcc_timecare/services/vital_reading.dart';
import 'package:tcc_timecare/services/vital_minute_display.dart';
import 'package:tcc_timecare/services/vital_occurrence_analyzer.dart';
import 'package:tcc_timecare/widgets/vital_quality_notice.dart';

/// Displays the readings published by the ESP32 under
/// `user_test/sinais_vitais`. Both a list keyed by timestamp and a map of
/// readings are supported, so older firmware does not break the application.
class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key, this.database});
  final RealtimeDatabaseRest? database;

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  late final _database = widget.database ?? RealtimeDatabaseRest.instance;
  late Future<Object?> _vitalsFuture;
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
    try {
      await _vitalsFuture;
    } catch (_) {
      /* Rendered by FutureBuilder. */
    }
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
      final data = VitalReportPdf.readingRows(selectedReadings);
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
          FutureBuilder<Object?>(
            future: _vitalsFuture,
            builder: (context, snapshot) {
              final readings = VitalReading.parse(snapshot.data);
              return IconButton(
                icon: const Icon(Icons.picture_as_pdf_outlined),
                tooltip: 'Exportar medições em PDF',
                onPressed:
                    snapshot.connectionState != ConnectionState.done ||
                        snapshot.hasError ||
                        readings.isEmpty
                    ? null
                    : () => _exportPdf(readings),
              );
            },
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
            return _ErrorState(onRetry: _refresh);
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = VitalReading.parse(snapshot.data);
          final persistentEpisodes = const VitalOccurrenceAnalyzer()
              .analyze(all)
              .where((e) => e.sustained)
              .toList();
          final limit = DateTime.now().subtract(Duration(days: _days));
          final readings = all
              .where((item) => item.timestamp.isAfter(limit))
              .toList();
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
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
                VitalQualityNotice(readings: readings),
                const SizedBox(height: 20),
                Text(
                  'Medições por minuto',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Text(
                  'Valores aproximados pela mediana de cada minuto. PDF com todas as leituras.',
                ),
                const SizedBox(height: 8),
                if (readings.isEmpty)
                  const _EmptyState()
                else
                  ...VitalMinuteDisplay.group(readings)
                      .take(30)
                      .map(
                        (reading) => _ReadingCard(
                          reading: reading,
                          isOutlier: reading.readings.any(
                            (r) => persistentEpisodes.any(
                              (e) =>
                                  e.simulated == r.simulated &&
                                  e.samples.any(
                                    (sample) =>
                                        sample.sample.timestamp == r.timestamp,
                                  ),
                            ),
                          ),
                        ),
                      ),
              ],
            ),
          );
        },
      ),
    );
  }
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
            style: TextStyle(color: foreground),
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
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: items
              .map(
                (item) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(item.icon, color: item.color),
                        const SizedBox(height: 12),
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
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          item.baseline.isReady
                              ? 'Mediana: ${item.baseline.personalMedian!.toStringAsFixed(1)} ${item.unit}${item.baseline.canScore ? '' : ' (MAD zero; sem escore)'}'
                              : 'Referência inicial: ${item.baseline.samples.length}/${item.baseline.config.minimumSamples} leituras válidas (sem espera em dias)',
                          style: TextStyle(
                            fontSize: 14,
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
  final VitalMinuteDisplay reading;
  final bool isOutlier;
  @override
  Widget build(BuildContext context) {
    final metrics = <String>[];
    if (reading.median(VitalMetric.heartRate) != null) {
      metrics.add('${reading.median(VitalMetric.heartRate)!.round()} bpm');
    }
    if (reading.median(VitalMetric.spo2) != null) {
      metrics.add(
        '${reading.median(VitalMetric.spo2)!.toStringAsFixed(0)}% SpO₂',
      );
    }
    if (reading.median(VitalMetric.temperature) != null) {
      metrics.add(
        '${reading.median(VitalMetric.temperature)!.toStringAsFixed(1)} °C',
      );
    }
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.monitor_heart_outlined)),
        title: Text(
          metrics.isEmpty ? 'Medição indisponível' : metrics.join(' • '),
        ),
        subtitle: Text(
          '${DateFormat("dd/MM/yyyy 'às' HH:mm").format(reading.timestamp)}${reading.simulated ? ' • SIMULADA' : ''}${isOutlier ? ' • Alteração persistente no minuto' : ''}'
          '${reading.readings.any((r) => r.hasQualityIssue || r.hasUnreportedQuality || r.hasUnconfirmedSignal) ? '\n${reading.readings.where((r) => r.hasQualityIssue || r.hasUnreportedQuality || r.hasUnconfirmedSignal).map((r) => r.qualityDescription).toSet().join('; ')}' : ''}',
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
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Não foi possível carregar os sinais vitais.',
            textAlign: TextAlign.center,
          ),
          TextButton(onPressed: onRetry, child: const Text('Tentar novamente')),
        ],
      ),
    ),
  );
}
