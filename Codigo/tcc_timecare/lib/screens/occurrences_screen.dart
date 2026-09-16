import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tcc_timecare/services/realtime_database_rest.dart';
import 'package:tcc_timecare/services/vital_baseline_algorithm.dart';
import 'package:tcc_timecare/services/vital_reading.dart';

class OccurrencesScreen extends StatefulWidget {
  const OccurrencesScreen({super.key, this.database});
  final RealtimeDatabaseRest? database;
  @override
  State<OccurrencesScreen> createState() => _OccurrencesScreenState();
}

class _OccurrencesScreenState extends State<OccurrencesScreen> {
  late final _database = widget.database ?? RealtimeDatabaseRest.instance;
  late Future<Object?> _future;
  @override
  void initState() {
    super.initState();
    _future = _database.get('user_test/sinais_vitais');
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _database.get('user_test/sinais_vitais');
    });
    try {
      await _future;
    } catch (_) {
      /* Rendered by FutureBuilder. */
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Ocorrências'),
      actions: [
        IconButton(
          tooltip: 'Atualizar ocorrências',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<Object?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Não foi possível carregar as ocorrências.',
                  textAlign: TextAlign.center,
                ),
                TextButton(
                  onPressed: _refresh,
                  child: const Text('Tentar novamente'),
                ),
              ],
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final readings = VitalReading.parse(snapshot.data);
        final occurrences = _occurrences(readings);
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    occurrences.isEmpty
                        ? 'Nenhum desvio sinalizado. Isso também pode ocorrer por histórico insuficiente ou MAD zero; não significa normalidade. Análise experimental: 20 leituras, intervalo mínimo de 14 dias, janela de 30 dias. Dados simulados são analisados separadamente.'
                        : '${occurrences.length} ocorrência(s) marcada(s). Análise estatística experimental, sem diagnóstico; confira a medição e considere orientação profissional se necessário.',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ...occurrences.map(
                (item) => Card(
                  child: ListTile(
                    leading: const Icon(
                      Icons.info_outline,
                      color: Colors.orange,
                    ),
                    title: Text(item.description),
                    subtitle: Text(
                      DateFormat("dd/MM/yyyy 'às' HH:mm").format(item.time),
                    ),
                    trailing: Text('z ${item.z.toStringAsFixed(1)}'),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  List<_Occurrence> _occurrences(List<VitalReading> readings) {
    const analyzer = VitalBaselineAnalyzer();
    final output = <_Occurrence>[];
    for (final simulated in [false, true]) {
      for (final entry
          in <(VitalMetric, String, double? Function(VitalReading))>[
            (VitalMetric.heartRate, 'Frequência cardíaca', (r) => r.heartRate),
            (VitalMetric.spo2, 'Oxigenação', (r) => r.spo2),
            (VitalMetric.temperature, 'Temperatura', (r) => r.temperature),
          ]) {
        final result = analyzer.analyze(
          entry.$1,
          readings
              .where((r) => entry.$3(r) != null && r.simulated == simulated)
              .map(
                (r) => VitalSample(timestamp: r.timestamp, value: entry.$3(r)!),
              ),
        );
        if (!result.isReady) continue;
        for (final sample in result.samples.where((s) => s.isOutlier)) {
          output.add(
            _Occurrence(
              sample.sample.timestamp,
              '${simulated ? 'SIMULADA • ' : ''}${entry.$2}: ${sample.sample.value.toStringAsFixed(1)}',
              sample.robustZScore!.abs(),
            ),
          );
        }
      }
    }
    output.sort((a, b) => b.time.compareTo(a.time));
    return output;
  }
}

class _Occurrence {
  const _Occurrence(this.time, this.description, this.z);
  final DateTime time;
  final String description;
  final double z;
}
