import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tcc_timecare/services/realtime_database_rest.dart';
import 'package:tcc_timecare/services/vital_occurrence_analyzer.dart';
import 'package:tcc_timecare/services/vital_reading.dart';
import 'package:tcc_timecare/widgets/vital_quality_notice.dart';

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
        final episodes = const VitalOccurrenceAnalyzer().analyze(readings);
        final occurrences = episodes.where((e) => e.sustained).toList();
        final unconfirmed = episodes.where((e) => !e.sustained).toList();
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
                        ? 'Nenhuma alteração persistente identificada. Histórico insuficiente ou pouca variação também podem impedir a avaliação; isso não significa normalidade.'
                        : '${occurrences.length} episódio(s) persistente(s). Leituras repetidas agrupadas por parâmetro, sem diagnóstico.',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              VitalQualityNotice(readings: readings),
              const Text(
                'A alteração precisa se repetir por pelo menos 40 segundos. Falhas de coleta interrompem a confirmação. Persistência não comprova a causa.',
              ),
              const SizedBox(height: 12),
              ...occurrences.map((item) => _EpisodeCard(episode: item)),
              if (unconfirmed.isNotEmpty)
                ExpansionTile(
                  title: const Text('Desvios não confirmados'),
                  subtitle: const Text(
                    'Picos breves ou sem continuidade. Repita a medição; podem ser alterações reais ou artefatos.',
                  ),
                  children: unconfirmed
                      .map((item) => _EpisodeCard(episode: item))
                      .toList(),
                ),
            ],
          ),
        );
      },
    ),
  );
}

class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({required this.episode});
  final VitalEpisode episode;

  @override
  Widget build(BuildContext context) {
    final e = episode;
    final date = DateFormat('dd/MM HH:mm:ss');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${e.simulated ? 'SIMULADO • ' : ''}${e.label}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              e.sustained
                  ? 'Alteração persistente'
                  : 'Sem confirmação temporal',
              style: TextStyle(
                color: e.sustained
                    ? Colors.orange
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              '${e.extreme.toStringAsFixed(1)} ${e.unit} • ${e.above ? 'acima' : 'abaixo'} da referência pessoal',
            ),
            Text(
              '${date.format(e.start)} — ${DateFormat('HH:mm:ss').format(e.end)}',
            ),
            Text('Duração observada: ${e.duration.inSeconds} s'),
            if (e.sustained)
              const Text(
                'Confira o sensor e repita a medição. A persistência também pode ocorrer em falhas contínuas do sensor.',
              ),
          ],
        ),
      ),
    );
  }
}
