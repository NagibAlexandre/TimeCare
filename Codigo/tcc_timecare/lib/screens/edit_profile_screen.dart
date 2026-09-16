import 'package:flutter/material.dart';
import 'package:tcc_timecare/services/patient_profile.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.initialData});
  final Map<Object?, Object?> initialData;
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final _name = TextEditingController(
    text: '${widget.initialData['name'] ?? ''}',
  );
  late final _email = TextEditingController(
    text: '${widget.initialData['email'] ?? ''}',
  );
  late final _age = TextEditingController(
    text: '${widget.initialData['idade'] ?? widget.initialData['age'] ?? ''}',
  );
  late final _phone = TextEditingController(
    text:
        '${widget.initialData['telefone'] ?? widget.initialData['phone'] ?? ''}',
  );
  late final _gender = TextEditingController(
    text: '${widget.initialData['genderIdentity'] ?? ''}',
  );
  late final _conditions = TextEditingController(
    text: '${widget.initialData['diagnosedConditions'] ?? ''}',
  );
  String _sex = 'Não informado';
  String _pregnancy = 'Não informado';
  String _oxygen = 'Não informado';
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _sex = '${widget.initialData['sexAtBirth'] ?? _sex}';
    _pregnancy = '${widget.initialData['pregnancyStatus'] ?? _pregnancy}';
    _oxygen = '${widget.initialData['supplementalOxygen'] ?? _oxygen}';
  }

  @override
  void dispose() {
    for (final item in [_name, _email, _age, _phone, _gender, _conditions]) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o nome do paciente.')),
      );
      return;
    }
    if (_saving) return;
    final age = int.tryParse(_age.text.trim());
    if (_age.text.trim().isNotEmpty && (age == null || age < 0 || age > 130)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe uma idade válida, de 0 a 130 anos.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await patientProfile.save({
        'name': _name.text.trim(),
        'email': _email.text.trim(),
        'idade': age,
        'telefone': _phone.text.trim(),
        'sexAtBirth': _sex,
        'genderIdentity': _gender.text.trim(),
        'pregnancyStatus': _pregnancy,
        'supplementalOxygen': _oxygen,
        'diagnosedConditions': _conditions.text.trim(),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível salvar o perfil.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Dados do paciente'),
      actions: [
        TextButton(
          onPressed: _saving ? null : _save,
          child: const Text('Salvar'),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Identificação',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _field(_name, 'Nome completo', Icons.person_outline),
        _field(
          _email,
          'E-mail',
          Icons.email_outlined,
          type: TextInputType.emailAddress,
        ),
        _field(_age, 'Idade', Icons.cake_outlined, type: TextInputType.number),
        _field(
          _phone,
          'Telefone',
          Icons.phone_outlined,
          type: TextInputType.phone,
        ),
        const SizedBox(height: 12),
        const Text(
          'Contexto clínico',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _dropdown('Sexo ao nascer', _sex, const [
          'Não informado',
          'Feminino',
          'Masculino',
          'Intersexo',
        ], (value) => setState(() => _sex = value!)),
        _field(
          _gender,
          'Identidade de gênero (opcional)',
          Icons.badge_outlined,
        ),
        _dropdown(
          'Status de gestação',
          _pregnancy,
          const ['Não informado', 'Não', 'Sim', 'Não se aplica'],
          (value) => setState(() => _pregnancy = value!),
        ),
        _dropdown(
          'Oxigênio suplementar no momento',
          _oxygen,
          const ['Não informado', 'Não', 'Sim'],
          (value) => setState(() => _oxygen = value!),
        ),
        _field(
          _conditions,
          'Condições diagnosticadas',
          Icons.medical_information_outlined,
          lines: 3,
          helper:
              'Ex.: hipertensão, DPOC. Não use este campo para autodiagnóstico.',
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: const Text('Salvar dados do paciente'),
        ),
      ],
    ),
  );
  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType? type,
    int lines = 1,
    String? helper,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      enabled: !_saving,
      controller: controller,
      keyboardType: type,
      maxLines: lines,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 3,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
    ),
  );
  Widget _dropdown(
    String label,
    String value,
    List<String> items,
    ValueChanged<String?> onChanged,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: DropdownButtonFormField(
      initialValue: items.contains(value) ? value : items.first,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: items
          .map((item) => DropdownMenuItem(value: item, child: Text(item)))
          .toList(),
      isExpanded: true,
      onChanged: _saving ? null : onChanged,
    ),
  );
}
