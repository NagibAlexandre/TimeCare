import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tcc_timecare/screens/analysis_screen.dart';
import 'package:tcc_timecare/screens/occurrences_screen.dart';
import 'package:tcc_timecare/services/realtime_database_rest.dart';

void main() {
  RealtimeDatabaseRest database(Map<String, Object?> records) =>
      RealtimeDatabaseRest(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode(records),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );

  testWidgets(
    'summary and cards omit failed BPM but keep high and low values',
    (tester) async {
      final now = DateTime.now();
      final db = database({
        'high': {
          'timestamp': now
              .subtract(const Duration(seconds: 3))
              .millisecondsSinceEpoch,
          'bpm': 120,
          'bpm_status': 'unvalidated_estimate',
        },
        'low': {
          'timestamp': now
              .subtract(const Duration(seconds: 2))
              .millisecondsSinceEpoch,
          'bpm': 40,
          'bpm_status': 'unvalidated_estimate',
        },
        'bad': {
          'timestamp': now
              .subtract(const Duration(seconds: 1))
              .millisecondsSinceEpoch,
          'bpm': 250,
          'bpm_status': 'acquisition_gap',
          'temperatura': 39.2,
          'temperature_status': 'unvalidated_estimate',
        },
      });
      await tester.pumpWidget(MaterialApp(home: AnalysisScreen(database: db)));
      await tester.pumpAndSettle();
      expect(find.text('Média: 80.0 bpm'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('BPM: Falha durante a coleta'),
        300,
      );
      expect(
        find.descendant(
          of: find.byType(ListTile),
          matching: find.textContaining('39.2 °C'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('250 bpm'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'occurrences retain above and below reference, excluding failed reading',
    (tester) async {
      final now = DateTime.now();
      final rows = <String, Object?>{
        for (var i = 0; i < 20; i++)
          '$i': {
            'timestamp': now
                .subtract(Duration(days: i + 1))
                .millisecondsSinceEpoch,
            'bpm': 69 + i % 3,
            'bpm_status': 'unvalidated_estimate',
          },
        'high': {
          'timestamp': now
              .subtract(const Duration(minutes: 1))
              .millisecondsSinceEpoch,
          'bpm': 160,
          'bpm_status': 'unvalidated_estimate',
        },
        'low': {
          'timestamp': now
              .subtract(const Duration(minutes: 2))
              .millisecondsSinceEpoch,
          'bpm': 40,
          'bpm_status': 'unvalidated_estimate',
        },
        'bad': {
          'timestamp': now
              .subtract(const Duration(minutes: 3))
              .millisecondsSinceEpoch,
          'bpm': 250,
          'bpm_status': 'acquisition_gap',
        },
      };
      await tester.pumpWidget(
        MaterialApp(home: OccurrencesScreen(database: database(rows))),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Nenhuma alteração persistente'),
        findsOneWidget,
      );
      await tester.tap(find.text('Desvios não confirmados'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('160.0 bpm • acima da referência pessoal'),
        findsOneWidget,
      );
      expect(
        find.textContaining('40.0 bpm • abaixo da referência pessoal'),
        findsOneWidget,
      );
      expect(find.textContaining('250.0'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('all-unavailable records remain visible at large text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = database({
      'bad': {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'bpm_status': 'no_contact',
        'spo2_status': 'no_contact',
        'temperature_status': 'sensor_unavailable',
      },
    });
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: AnalysisScreen(database: db),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Medição indisponível'),
      300,
      maxScrolls: 20,
    );
    expect(find.textContaining('Sem contato com o sensor'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
