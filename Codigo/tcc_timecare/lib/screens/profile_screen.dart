import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tcc_timecare/screens/edit_profile_screen.dart';
import 'package:tcc_timecare/services/app_preferences.dart';
import 'package:tcc_timecare/services/patient_profile.dart';
import 'package:tcc_timecare/widgets/patient_avatar.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.profile});
  final PatientProfile? profile;
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final _profile = widget.profile ?? patientProfile;
  bool _savingPhoto = false;
  late Future<Object?> _future;
  bool _loadedPreferences = false;

  @override
  void initState() {
    super.initState();
    _future = _profile.load();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _profile.load();
    });
    try {
      await _future;
    } catch (_) {
      /* The error state offers a retry. */
    }
  }

  Future<void> _savePreferences() async {
    try {
      await _profile.save({
        'preferences': {
          'theme': appPreferences.themeMode.name,
          'textScale': appPreferences.textScale,
          'highContrast': appPreferences.highContrast,
        },
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível salvar a aparência. Tente novamente.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _pickPhoto() async {
    if (_savingPhoto) return;
    setState(() => _savingPhoto = true);
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 360,
        imageQuality: 70,
      );
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (bytes.length > 2 * 1024 * 1024) {
        throw const FormatException('Imagem muito grande');
      }
      await _profile.save({'photoBase64': base64Encode(bytes)});
      if (mounted) {
        setState(() => _future = Future.value(_profile.data));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Foto de perfil salva.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível salvar a foto.')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingPhoto = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Perfil')),
    body: FutureBuilder<Object?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Não foi possível carregar o perfil.'),
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
        final data = snapshot.data is Map
            ? Map<Object?, Object?>.from(snapshot.data as Map)
            : <Object?, Object?>{};
        _applySavedPreferences(data['preferences']);
        final name = '${data['name'] ?? 'Paciente'}';
        final email = '${data['email'] ?? 'Adicione seu e-mail'}';
        final age = data['idade'] ?? data['age'];

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    PatientAvatar(data: data, radius: 48),
                    IconButton.filledTonal(
                      onPressed: _savingPhoto ? null : _pickPhoto,
                      icon: _savingPhoto
                          ? const SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.camera_alt_outlined),
                      tooltip: 'Alterar foto',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  name,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Center(
                child: Text(
                  age == null || '$age'.isEmpty ? email : '$email • $age anos',
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              _appearanceCard(),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Dados do paciente'),
                  subtitle: const Text(
                    'Identificação, contato e informações de saúde',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EditProfileScreen(initialData: data),
                      ),
                    );
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
          const Text(
            'Acessibilidade e aparência',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<ThemeMode>(
            key: ValueKey(appPreferences.themeMode),
            isExpanded: true,
            initialValue: appPreferences.themeMode,
            decoration: const InputDecoration(labelText: 'Tema'),
            items: const [
              DropdownMenuItem(
                value: ThemeMode.system,
                child: Text('Seguir o aparelho'),
              ),
              DropdownMenuItem(value: ThemeMode.light, child: Text('Claro')),
              DropdownMenuItem(value: ThemeMode.dark, child: Text('Escuro')),
            ],
            onChanged: (value) {
              setState(() => appPreferences.update(themeMode: value));
              _savePreferences();
            },
          ),
          const SizedBox(height: 20),
          const Text('Tamanho do texto'),
          Slider(
            value: appPreferences.textScale,
            min: .9,
            max: 1.4,
            divisions: 5,
            label: '${(appPreferences.textScale * 100).round()}%',
            onChanged: (value) =>
                setState(() => appPreferences.update(textScale: value)),
            onChangeEnd: (_) => _savePreferences(),
          ),
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
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => appPreferences.update(
        themeMode: ThemeMode.values.firstWhere(
          (item) => item.name == data['theme'],
          orElse: () => ThemeMode.system,
        ),
        textScale: data['textScale'] is num
            ? (data['textScale'] as num).toDouble()
            : 1,
        highContrast: data['highContrast'] == true,
      ),
    );
  }
}
