// ignore_for_file: unnecessary_null_comparison
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/cupertino.dart';
import 'package:tcc_timecare/services/realtime_database_rest.dart';

class MedicineScreen extends StatefulWidget {
  const MedicineScreen({super.key});

  @override
  State<MedicineScreen> createState() => _MedicineScreenState();
}

class _MedicineScreenState extends State<MedicineScreen> {
  final _database = RealtimeDatabaseRest.instance;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  final TextEditingController _dosageController = TextEditingController();
  final TextEditingController _instructionsController = TextEditingController();
  TimeOfDay? _selectedTime;

  late Future<Object?> _medicinesFuture;
  late Future<Object?> _userFuture;

  @override
  void initState() {
    super.initState();
    // Avoid Firebase EventChannels on Windows: their native database SDK can
    // dispatch callbacks off the platform thread and terminate the app.
    _medicinesFuture = _database.get('user_test/remedios');
    _userFuture = _database.get('user_test');
  }

  Future<void> _reloadData() async {
    setState(() {
      _medicinesFuture = _database.get('user_test/remedios');
      _userFuture = _database.get('user_test');
    });
    await _medicinesFuture;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _timeController.dispose();
    _dosageController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  Future<void> _selectTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: CupertinoColors.systemBlue,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedTime = picked;
        _timeController.text = _formatTimeOfDay(picked);
      });
    }
  }

  String _formatTimeOfDay(TimeOfDay tod) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, tod.hour, tod.minute);
    return DateFormat('HH:mm').format(dt);
  }

  String _formatTimeOfDayAsIso8601(TimeOfDay tod) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, tod.hour, tod.minute);
    return dt.toUtc().toIso8601String(); // Format as ISO 8601 UTC string
  }

  void _showModernNotification(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    final overlay = Overlay.of(context);
    final overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 10,
        left: 20,
        right: 20,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isError
                  ? CupertinoColors.destructiveRed.withValues(alpha: 0.9)
                  : CupertinoColors.systemGreen.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  isError
                      ? CupertinoIcons.exclamationmark_circle
                      : CupertinoIcons.checkmark_circle,
                  color: CupertinoColors.white,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: CupertinoColors.white,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);
    Future.delayed(const Duration(seconds: 3), () {
      overlayEntry.remove();
    });
  }

  TimeOfDay _parseTimeOfDayFromIso8601(String iso8601String) {
    final dateTime = DateTime.tryParse(iso8601String)?.toLocal();
    return dateTime == null
        ? TimeOfDay.now()
        : TimeOfDay.fromDateTime(dateTime);
  }

  Future<void> _addMedicine() async {
    if (_nameController.text.isEmpty || _timeController.text.isEmpty) {
      _showModernNotification(
        context,
        'Preencha todos os campos',
        isError: true,
      );
      return;
    }

    try {
      await _database.push('user_test/remedios', {
        'name': _nameController.text,
        'dosage': _dosageController.text,
        'scheduled_time': _formatTimeOfDayAsIso8601(
          _selectedTime!,
        ), // Format selected time
        'instructions': _instructionsController.text,
        'status': 'off-time', // Default status
        // 'createdAt': ServerValue.timestamp, // Removed as per new structure
        // 'bit': false, // Removed as per new structure
      });

      _nameController.clear();
      _timeController.clear();
      _dosageController.clear();
      _instructionsController.clear();
      _selectedTime = null;
      await _reloadData();

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _showModernNotification(context, 'Medicamento adicionado com sucesso');
    } catch (e) {
      if (!mounted) return;
      _showModernNotification(context, 'Erro ao adicionar: $e', isError: true);
    }
  }

  Future<void> _deleteMedicine(String key) async {
    try {
      await _database.delete('user_test/remedios/$key');
      await _reloadData();
      if (!mounted) return;
      _showModernNotification(context, 'Medicamento removido com sucesso');
    } catch (e) {
      if (!mounted) return;
      _showModernNotification(context, 'Erro ao remover: $e', isError: true);
    }
  }

  Future<void> _editMedicine(
    String key,
    Map<dynamic, dynamic> currentMedicine,
  ) async {
    // Retrieve the new fields
    final currentName = currentMedicine['name'] ?? '';
    final currentScheduledTime = currentMedicine['scheduled_time'] ?? '';
    final currentDosage = currentMedicine['dosage'] ?? '';
    final currentInstructions = currentMedicine['instructions'] ?? '';

    _nameController.text = currentName;
    _dosageController.text = currentDosage;
    _instructionsController.text = currentInstructions;

    if (currentScheduledTime.isNotEmpty) {
      _selectedTime = _parseTimeOfDayFromIso8601(currentScheduledTime);
      _timeController.text = _formatTimeOfDay(
        _selectedTime!,
      ); // Format for display in the text field
    } else {
      _selectedTime = null;
      _timeController.text = '';
    }

    if (!mounted) return;
    showCupertinoModalPopup(
      context: context,
      builder: (BuildContext context) {
        return CupertinoActionSheet(
          title: const Text('Editar Remédio'),
          message: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                CupertinoTextField(
                  controller: _nameController,
                  placeholder: 'Nome do Remédio',
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: CupertinoColors.systemGrey4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 16),
                CupertinoTextField(
                  controller: _dosageController,
                  placeholder: 'Dosagem',
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: CupertinoColors.systemGrey4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 16),
                CupertinoTextField(
                  controller: _instructionsController,
                  placeholder: 'Instruções',
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: CupertinoColors.systemGrey4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 16),
                CupertinoTextField(
                  controller: _timeController,
                  placeholder: 'Horário',
                  readOnly: true,
                  onTap: () => _selectTime(context),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: CupertinoColors.systemGrey4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  suffix: const Padding(
                    padding: EdgeInsets.only(right: 8.0),
                    child: Icon(CupertinoIcons.time),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            CupertinoActionSheetAction(
              onPressed: () async {
                try {
                  // Only update name and scheduled_time for now
                  await _database.patch('user_test/remedios/$key', {
                    'name': _nameController.text,
                    'dosage': _dosageController.text,
                    'scheduled_time': _selectedTime != null
                        ? _formatTimeOfDayAsIso8601(_selectedTime!)
                        : '',
                    'instructions': _instructionsController.text,
                    // status is not updated here
                  });
                  _nameController.clear();
                  _timeController.clear();
                  _dosageController.clear();
                  _instructionsController.clear();
                  _selectedTime = null;
                  await _reloadData();
                  if (!mounted) return;
                  Navigator.of(context, rootNavigator: true).pop();
                  _showModernNotification(
                    context,
                    'Medicamento atualizado com sucesso',
                  );
                } catch (e) {
                  if (!mounted) return;
                  _showModernNotification(
                    context,
                    'Erro ao atualizar: $e',
                    isError: true,
                  );
                }
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.pencil),
                  SizedBox(width: 8),
                  Text('Salvar'),
                ],
              ),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
            child: const Text('Cancelar'),
          ),
        );
      },
    );
  }

  Future<void> _showDeleteConfirmation(String key) async {
    if (!mounted) return;
    showCupertinoModalPopup(
      context: context,
      builder: (BuildContext context) {
        return CupertinoActionSheet(
          title: const Text('Confirmar exclusão'),
          message: const Text(
            'Tem certeza que deseja excluir este medicamento?',
          ),
          actions: [
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.of(context, rootNavigator: true).pop();
                _deleteMedicine(key);
              },
              child: const Text('Excluir'),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
            child: const Text('Cancelar'),
          ),
        );
      },
    );
  }

  Future<void> _deleteAllMedicines() async {
    try {
      // Get a snapshot of the data under the remedios node
      final medicinesValue = await _database.get('user_test/remedios');

      if (medicinesValue is Map) {
        final Map<dynamic, dynamic> medicinesMap = Map<dynamic, dynamic>.from(
          medicinesValue,
        );

        // Iterate through each medicine entry and delete it individually
        for (final key in medicinesMap.keys) {
          await _database.delete('user_test/remedios/$key');
        }
        await _reloadData();

        if (!mounted) return;
        _showModernNotification(
          context,
          'Todos os medicamentos removidos com sucesso.',
        );
      } else {
        if (!mounted) return;
        _showModernNotification(
          context,
          'Não há medicamentos para remover.',
          isError: false,
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showModernNotification(
        context,
        'Erro ao remover medicamentos: $e',
        isError: true,
      );
    }
  }

  void _showDeleteAllConfirmation() {
    if (!mounted) return;
    showCupertinoModalPopup(
      context: context,
      builder: (BuildContext context) {
        return CupertinoActionSheet(
          title: const Text('Confirmar exclusão de todos os medicamentos'),
          message: const Text(
            'Tem certeza que deseja excluir TODOS os medicamentos? Esta ação não pode ser desfeita.',
          ),
          actions: [
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.of(context, rootNavigator: true).pop();
                _deleteAllMedicines();
              },
              child: const Text('Excluir Todos'),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
            child: const Text('Cancelar'),
          ),
        );
      },
    );
  }

  void _showAddMedicineDialog() {
    showCupertinoModalPopup(
      context: context,
      builder: (BuildContext context) {
        return CupertinoActionSheet(
          title: const Text('Adicionar Remédio'),
          message: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                CupertinoTextField(
                  controller: _nameController,
                  placeholder: 'Nome do Remédio',
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: CupertinoColors.systemGrey4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 16),
                CupertinoTextField(
                  controller: _dosageController,
                  placeholder: 'Dosagem',
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: CupertinoColors.systemGrey4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 16),
                CupertinoTextField(
                  controller: _instructionsController,
                  placeholder: 'Instruções',
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: CupertinoColors.systemGrey4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 16),
                CupertinoTextField(
                  controller: _timeController,
                  placeholder: 'Horário',
                  readOnly: true,
                  onTap: () => _selectTime(context),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: CupertinoColors.systemGrey4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  suffix: const Padding(
                    padding: EdgeInsets.only(right: 8.0),
                    child: Icon(CupertinoIcons.time),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            CupertinoActionSheetAction(
              onPressed: _addMedicine,
              child: const Text('Adicionar'),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
            child: const Text('Cancelar'),
          ),
        );
      },
    );
  }

  Future<void> _updateMedicineStatus(String key, String newStatus) async {
    try {
      await _database.patch('user_test/remedios/$key', {'status': newStatus});
      await _reloadData();
      if (!mounted) return;
      _showModernNotification(context, 'Status atualizado para $newStatus');
    } catch (e) {
      if (!mounted) return;
      _showModernNotification(
        context,
        'Erro ao atualizar status: $e',
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        elevation: 0,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // StreamBuilder for user data
              FutureBuilder<Object?>(
                future: _userFuture,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Text(
                      'Erro: ${snapshot.error}',
                      style: TextStyle(color: CupertinoColors.systemRed),
                    );
                  }

                  if (!snapshot.hasData) {
                    return const CupertinoActivityIndicator(); // Loading indicator while fetching user data
                  }

                  // Extract user data
                  final userValue = snapshot.data;
                  final userData = userValue is Map
                      ? Map<dynamic, dynamic>.from(userValue)
                      : <dynamic, dynamic>{};
                  final userName =
                      userData?['name'] ??
                      'Nome do Usuário'; // Assuming name is stored under 'nome'

                  return Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: CupertinoColors
                              .systemBlue, // Changed color to a primary blue
                          borderRadius: BorderRadius.circular(
                            20,
                          ), // Keep it circular
                        ),
                        child: const Icon(
                          CupertinoIcons.person,
                          color: Colors.white, // Keep icon color white
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            userName, // Display fetched user name
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            (userData?['idade'] ?? 13)
                                .toString(), // Convert int to String
                            style: TextStyle(
                              fontSize: 14,
                              color: CupertinoColors.systemGrey,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Meus Remédios',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          CupertinoIcons.paintbrush,
                          color: CupertinoColors.systemRed,
                        ),
                        onPressed: () {
                          _showDeleteAllConfirmation();
                        },
                      ),
                      IconButton(
                        icon: const Icon(
                          CupertinoIcons.arrow_counterclockwise,
                          color: CupertinoColors.systemGrey,
                        ),
                        onPressed: _reloadData,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        toolbarHeight: 120, // Adjust height to accommodate the custom title
      ),
      body: FutureBuilder<Object?>(
        future: _medicinesFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Erro: ${snapshot.error}'));
          }

          if (!snapshot.hasData) {
            return const Center(child: CupertinoActivityIndicator());
          }

          final rawMedicines = snapshot.data;
          final medicinesMap = rawMedicines is Map
              ? Map<dynamic, dynamic>.from(rawMedicines)
              : null;
          if (medicinesMap == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    CupertinoIcons.heart,
                    size: 64,
                    color: CupertinoColors.systemGrey,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Nenhum medicamento cadastrado',
                    style: TextStyle(
                      fontSize: 18,
                      color: CupertinoColors.systemGrey,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Removed the add button from here
                ],
              ),
            );
          }

          final medicinesList = medicinesMap.entries
              .where((entry) => entry.value is Map)
              .map((entry) {
                final values = Map<dynamic, dynamic>.from(entry.value as Map);
                return {
                  'key': entry.key,
                  'name': values['name']?.toString() ?? '',
                  'dosage': values['dosage']?.toString() ?? '',
                  'scheduled_time': values['scheduled_time']?.toString() ?? '',
                  'instructions': values['instructions']?.toString() ?? '',
                  'status':
                      values['status'] ??
                      'unknown', // Default status if not present
                  // 'time': entry.value['time'] ?? '', // Removed old field
                  // 'bit': entry.value['bit'] ?? false, // Removed old field
                };
              })
              .toList();

          medicinesList.sort((a, b) {
            final timeA = a['scheduled_time'] as String;
            final timeB = b['scheduled_time'] as String;
            if (timeA.isEmpty && timeB.isEmpty) return 0;
            if (timeA.isEmpty) return 1;
            if (timeB.isEmpty) return -1;
            return timeA.compareTo(timeB);
          });

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: medicinesList.length, // Removed the +1
            itemBuilder: (context, index) {
              final medicine = medicinesList[index];
              // Use a custom Card structure instead of ListTile for better control
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                elevation: 2, // Add some elevation for depth
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12), // Rounded corners
                ),
                color: Theme.of(context).cardColor,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left side icon
                      GestureDetector(
                        onTap: () {
                          if (medicine['status'] != 'on-time' &&
                              medicine['status'] != 'late-time') {
                            showCupertinoModalPopup(
                              context: context,
                              builder: (BuildContext context) {
                                return CupertinoActionSheet(
                                  title: const Text('Alterar status'),
                                  message: const Text(
                                    'Deseja marcar este remédio como atrasado?',
                                  ),
                                  actions: [
                                    CupertinoActionSheetAction(
                                      onPressed: () {
                                        Navigator.pop(context);
                                        _updateMedicineStatus(
                                          medicine['key'],
                                          'late-time',
                                        );
                                      },
                                      child: const Text('Marcar como atrasado'),
                                    ),
                                  ],
                                  cancelButton: CupertinoActionSheetAction(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Cancelar'),
                                  ),
                                );
                              },
                            );
                          }
                        },
                        child: Icon(
                          medicine['status'] == 'on-time'
                              ? CupertinoIcons.checkmark_circle_fill
                              : medicine['status'] == 'late-time'
                              ? CupertinoIcons.clock_solid
                              : CupertinoIcons.circle_fill,
                          color: medicine['status'] == 'on-time'
                              ? CupertinoColors.systemGreen
                              : medicine['status'] == 'late-time'
                              ? CupertinoColors.systemYellow
                              : CupertinoColors.systemRed,
                          size: 24.0,
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Middle content
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              medicine['name'],
                              style: const TextStyle(
                                fontSize: 18, // Slightly larger font for name
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            // Displaying "Tipo" (assuming it's the 'instructions' field or similar,
                            // or maybe it's a hardcoded value in the image?)
                            // Based on OCR, "Tipo" has values like 321 and 132.
                            // Let's use the 'instructions' field for "Tipo" for now, as 'dosage' is
                            // already displayed as "Dosagem". If 'instructions' is empty, maybe
                            // display 'dosage' under "Tipo"? Or add a new field to the data?
                            // For now, let's assume 'instructions' is "Tipo".
                            if ((medicine['instructions'] as String).isNotEmpty)
                              Text(
                                'Tipo: ${medicine['instructions']}', // Assuming 'instructions' is 'Tipo'
                                style: TextStyle(
                                  fontSize: 15,
                                  color: CupertinoColors.systemGrey,
                                ),
                              ),
                            const SizedBox(height: 4),
                            if ((medicine['scheduled_time'] as String)
                                .isNotEmpty)
                              Text(
                                'Horário: ${_formatTimeOfDay(_parseTimeOfDayFromIso8601(medicine['scheduled_time']))}',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: CupertinoColors.systemGrey,
                                ),
                              ),
                            const SizedBox(height: 4),
                            if ((medicine['dosage'] as String).isNotEmpty)
                              Text(
                                'Dosagem: ${medicine['dosage']}',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: CupertinoColors.systemGrey,
                                ),
                              ),
                          ],
                        ),
                      ),
                      // Right side options button
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          showCupertinoModalPopup(
                            context: context,
                            builder: (BuildContext context) {
                              return CupertinoActionSheet(
                                title: Text(medicine['name']),
                                message: const Text('Escolha uma opção'),
                                actions: [
                                  CupertinoActionSheetAction(
                                    onPressed: () {
                                      Navigator.pop(context);
                                      _editMedicine(
                                        medicine['key'],
                                        Map<dynamic, dynamic>.from(
                                          medicinesMap[medicine['key']] as Map,
                                        ),
                                      );
                                    },
                                    child: const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(CupertinoIcons.pencil),
                                        SizedBox(width: 8),
                                        Text('Editar'),
                                      ],
                                    ),
                                  ),
                                  CupertinoActionSheetAction(
                                    isDestructiveAction: true,
                                    onPressed: () {
                                      Navigator.pop(context);
                                      _showDeleteConfirmation(medicine['key']);
                                    },
                                    child: const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(CupertinoIcons.delete),
                                        SizedBox(width: 8),
                                        Text('Excluir'),
                                      ],
                                    ),
                                  ),
                                ],
                                cancelButton: CupertinoActionSheetAction(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Cancelar'),
                                ),
                              );
                            },
                          );
                        },
                        child: const Icon(
                          CupertinoIcons.ellipsis,
                          color: CupertinoColors.systemGrey,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddMedicineDialog,
        backgroundColor: CupertinoColors.systemBlue,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15), // Rounded corners for FAB
        ),
        child: const Icon(CupertinoIcons.plus),
      ),
    );
  }
}
