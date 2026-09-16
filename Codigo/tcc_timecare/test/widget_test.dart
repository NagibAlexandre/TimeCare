import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tcc_timecare/main.dart';
import 'package:tcc_timecare/screens/medicines_screen.dart';
import 'package:tcc_timecare/screens/profile_screen.dart';
import 'package:tcc_timecare/screens/edit_profile_screen.dart';
import 'package:tcc_timecare/screens/analysis_screen.dart';
import 'package:tcc_timecare/screens/occurrences_screen.dart';
import 'package:tcc_timecare/services/patient_profile.dart';
import 'package:tcc_timecare/services/realtime_database_rest.dart';
import 'package:tcc_timecare/widgets/patient_avatar.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Screens fit 360px, $brightness, text $scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final database = RealtimeDatabaseRest(
          client: MockClient((_) async => http.Response('null', 200)),
        );
        for (final screen in <Widget>[
          MedicineScreen(database: database),
          ProfileScreen(profile: PatientProfile(database: database)),
          AnalysisScreen(database: database),
          OccurrencesScreen(database: database),
          const EditProfileScreen(initialData: {}),
        ]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: buildAppTheme(brightness),
              builder: (_, child) => MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: screen,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(tester.takeException(), isNull);
          for (
            var step = 0;
            step < 3 && find.byType(ListView).evaluate().isNotEmpty;
            step++
          ) {
            await tester.drag(
              find.byType(ListView).first,
              const Offset(0, -500),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
        }
      });
    }
  }
  testWidgets('PDF export becomes available when readings finish loading', (
    tester,
  ) async {
    final database = RealtimeDatabaseRest(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'a': {
              'timestamp': DateTime.now().millisecondsSinceEpoch,
              'bpm': 72,
            },
          }),
          200,
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: AnalysisScreen(database: database)),
    );
    await tester.pumpAndSettle();
    final button = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.picture_as_pdf_outlined),
    );
    expect(button.onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Profile failure can be retried', (tester) async {
    var calls = 0;
    final database = RealtimeDatabaseRest(
      client: MockClient(
        (_) async => ++calls == 1
            ? http.Response('unavailable', 503)
            : http.Response('{"name":"Ana"}', 200),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(profile: PatientProfile(database: database)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(find.text('Ana'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Saved photo renders after recreating screen', (tester) async {
    const photo =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII=';
    final database = RealtimeDatabaseRest(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'name': 'Ana Silva', 'photoBase64': photo}),
          200,
        ),
      ),
    );
    for (var i = 0; i < 2; i++) {
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(
            key: ValueKey(i),
            profile: PatientProfile(database: database),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(PatientAvatar),
          matching: find.byType(Image),
        ),
        findsOneWidget,
      );
      expect(find.text('Ana Silva'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
