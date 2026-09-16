import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tcc_timecare/screens/EditProfileScreen.dart';
import 'package:tcc_timecare/services/app_preferences.dart';
import 'package:tcc_timecare/services/realtime_database_rest.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _database = RealtimeDatabaseRest.instance;
  late Future<Object?> _future;
  bool _loadedPreferences = false;

  @override
  void initState() {
    super.initState();
    _future = _database.get('user_test');
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _database.get('user_test');
    });
    await _future;
  }

  Future<void> _savePreferences() => _database.patch('user_test', {
    'preferences': {
      'theme': appPreferences.themeMode.name,
      'textScale': appPreferences.textScale,
      'highContrast': appPreferences.highContrast,
    },
  });

  Future<void> _pickPhoto() async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 360,
        imageQuality: 70,
      );
      if (image == null) return;
      final bytes = await image.readAsBytes();
      await _database.patch('user_test', {'photoBase64': base64Encode(bytes)});
      if (mounted) await _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível salvar a foto.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Perfil'), centerTitle: true),
    body: FutureBuilder<Object?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Não foi possível carregar o perfil.'));
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final data = snapshot.data is Map
            ? Map<Object?, Object?>.from(snapshot.data as Map)
            : <Object?, Object?>{};
        _applySavedPreferences(data['preferences']);
        final name = '${data['name'] ?? 'Paciente'}';
        final email = '${data['email'] ?? 'Adicione seu e-mail'}';
        final age = data['idade'] ?? data['age'];
        final photo = _photoProvider(data['photoBase64'] as String?);
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    CircleAvatar(
                      radius: 48,
                      backgroundImage: photo,
                      child: photo == null ? Text(_initials(name)) : null,
                    ),
                    IconButton.filledTonal(
                      onPressed: _pickPhoto,
                      icon: const Icon(Icons.camera_alt_outlined),
                      tooltip: 'Alterar foto',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Center(child: Text(name, style: Theme.of(context).textTheme.titleLarge)),
              Center(child: Text(age == null ? email : '$email • $age anos')),
              const SizedBox(height: 24),
              _appearanceCard(),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Dados pessoais'),
                  subtitle: const Text('Nome, e-mail, idade e contato'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => EditProfileScreen(initialData: data)));
                    if (mounted) _refresh();
                  },
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  Widget _appearanceCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Acessibilidade e aparência', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('Sistema')),
              ButtonSegment(value: ThemeMode.light, label: Text('Claro')),
              ButtonSegment(value: ThemeMode.dark, label: Text('Escuro')),
            ],
            selected: {appPreferences.themeMode},
            onSelectionChanged: (value) {
              setState(() => appPreferences.update(themeMode: value.first));
              _savePreferences();
            },
          ),
          Row(children: [
            const Text('Tamanho do texto'),
            Expanded(child: Slider(value: appPreferences.textScale, min: .9, max: 1.4, divisions: 5, onChanged: (value) => setState(() => appPreferences.update(textScale: value)), onChangeEnd: (_) => _savePreferences())),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Alto contraste'),
            value: appPreferences.highContrast,
            onChanged: (value) {
              setState(() => appPreferences.update(highContrast: value));
              _savePreferences();
            },
          ),
        ],
      ),
    ),
  );

  void _applySavedPreferences(Object? value) {
    if (_loadedPreferences || value is! Map) return;
    _loadedPreferences = true;
    final data = Map<Object?, Object?>.from(value);
    WidgetsBinding.instance.addPostFrameCallback((_) => appPreferences.update(
      themeMode: ThemeMode.values.firstWhere((item) => item.name == data['theme'], orElse: () => ThemeMode.system),
      textScale: (data['textScale'] as num?)?.toDouble() ?? 1,
      highContrast: data['highContrast'] == true,
    ));
  }

  String _initials(String name) => name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).take(2).map((part) => part[0].toUpperCase()).join();
  ImageProvider? _photoProvider(String? encoded) { try { return encoded == null || encoded.isEmpty ? null : MemoryImage(base64Decode(encoded)); } catch (_) { return null; } }
}
