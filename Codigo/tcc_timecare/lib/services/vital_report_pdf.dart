import 'dart:typed_data';
import 'vital_baseline_algorithm.dart';
import 'vital_reading.dart';
import 'package:intl/intl.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class VitalReportPdf {
  /// Receives the same quality-filtered records used by summaries/occurrences.
  static List<Map<String, Object?>> readingRows(
    Iterable<VitalReading> readings,
  ) => readings
      .map(
        (item) => <String, Object?>{
          'time': DateFormat('HH:mm:ss').format(item.timestamp),
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
          'quality': item.qualityDescription,
        },
      )
      .toList();

  static Future<Uint8List> build({
    required Map<Object?, Object?> profile,
    required DateTime date,
    required List<Map<String, Object?>> readings,
  }) async {
    final document = pw.Document();
    final name = '${profile['name'] ?? 'Paciente'}';
    final email = '${profile['email'] ?? 'Não informado'}';
    final age = '${profile['idade'] ?? profile['age'] ?? 'Não informada'}';
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (context) => [
          pw.Text(
            'TimeCare',
            style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Recibo de medições de sinais vitais',
            style: const pw.TextStyle(fontSize: 15),
          ),
          pw.Divider(),
          pw.Text('Paciente: $name'),
          pw.Text('E-mail: $email'),
          pw.Text('Idade: $age'),
          pw.SizedBox(height: 16),
          pw.Text(
            'Data selecionada: ${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.Text('Total de registros: ${readings.length}'),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: const [
              'Horário',
              'Frequência',
              'SpO2',
              'Temperatura',
              'Origem',
              'Qualidade',
            ],
            data: readings
                .map(
                  (reading) => [
                    reading['time'],
                    reading['heartRate'],
                    reading['spo2'],
                    reading['temperature'],
                    reading['source'],
                    reading['quality'] ?? 'Qualidade não informada',
                  ],
                )
                .toList(),
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue700),
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            'Relatório descritivo, sem diagnóstico. Registros simulados são identificados na tabela. Ausência de marcador de simulação não comprova origem física.',
          ),
          pw.Text(
            'Valores indisponíveis ou inconclusivos aparecem como "-". '
            'Qualidade descreve verificações de aquisição, não validação clínica. '
            'Valores altos ou baixos não são excluídos por sua magnitude.',
          ),
          pw.Text(
            'Versão de análise do aplicativo: ${defaultVitalAlgorithmConfig.algorithmVersion}. Este PDF não contém escores nem classificações.',
          ),
          pw.Text(
            'Documento gerado pelo TimeCare em ${DateTime.now().toLocal()}.',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey),
          ),
        ],
      ),
    );
    return document.save();
  }
}
