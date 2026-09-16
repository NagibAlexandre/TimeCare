import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tcc_timecare/services/patient_profile.dart';
import 'package:tcc_timecare/services/realtime_database_rest.dart';
import 'package:tcc_timecare/services/app_preferences.dart';

void main() {
  test(
    'Photo persists across instances and personal data edits preserve it',
    () async {
      final stored = <String, Object?>{
        'name': 'Ana',
        'remedios': {
          'id': {'name': 'Teste'},
        },
      };
      final database = RealtimeDatabaseRest(
        client: MockClient((request) async {
          if (request.method == 'PATCH') {
            stored.addAll(
              Map<String, Object?>.from(jsonDecode(request.body) as Map),
            );
          }
          return http.Response(jsonEncode(stored), 200);
        }),
      );
      final profile = PatientProfile(database: database);
      await profile.load();
      await profile.save({'photoBase64': 'photo-bytes'});
      await profile.save({'name': 'Ana Silva'});
      final reopened = PatientProfile(database: database);
      await reopened.load();
      expect(reopened.data['photoBase64'], 'photo-bytes');
      expect(reopened.data['name'], 'Ana Silva');
      expect(reopened.data['remedios'], isNotNull);
    },
  );
  test('Failed upload keeps the last saved photo', () async {
    final database = RealtimeDatabaseRest(
      client: MockClient(
        (request) async => request.method == 'GET'
            ? http.Response('{"photoBase64":"old"}', 200)
            : http.Response('unavailable', 503),
      ),
    );
    final profile = PatientProfile(database: database);
    await profile.load();
    await expectLater(profile.save({'photoBase64': 'new'}), throwsStateError);
    expect(profile.data['photoBase64'], 'old');
  });
  test('A slow earlier read cannot replace a saved photo', () async {
    final pending = Completer<http.Response>();
    final database = RealtimeDatabaseRest(
      client: MockClient(
        (request) async =>
            request.method == 'GET' ? pending.future : http.Response('{}', 200),
      ),
    );
    final profile = PatientProfile(database: database);
    final loading = profile.load();
    await profile.save({'photoBase64': 'new'});
    pending.complete(http.Response('{"photoBase64":"old"}', 200));
    await loading;
    expect(profile.data['photoBase64'], 'new');
  });
  test('Invalid saved text scales cannot break accessibility controls', () {
    final preferences = AppPreferences();
    preferences.update(textScale: 100);
    expect(preferences.textScale, 1.4);
    preferences.update(textScale: double.nan);
    expect(preferences.textScale, 1);
  });
}
