import 'package:flutter/foundation.dart';
import 'package:tcc_timecare/services/realtime_database_rest.dart';

/// A single source of truth for the profile shown across tabs.
class PatientProfile extends ChangeNotifier {
  PatientProfile({RealtimeDatabaseRest? database})
    : _database = database ?? RealtimeDatabaseRest.instance;

  final RealtimeDatabaseRest _database;
  Map<Object?, Object?> _data = {};
  Map<Object?, Object?> get data => Map.unmodifiable(_data);
  int _revision = 0;

  Future<Object?> load() async {
    final revision = _revision;
    final value = await _database.get('user_test');
    // An earlier read must never replace a newly saved photo.
    if (revision == _revision) {
      _data = value is Map ? Map<Object?, Object?>.from(value) : {};
      notifyListeners();
    }
    return data;
  }

  Future<void> save(Map<String, Object?> changes) async {
    await _database.patch('user_test', changes);
    _revision++;
    _data = {..._data, ...changes};
    notifyListeners();
  }
}

final patientProfile = PatientProfile();
