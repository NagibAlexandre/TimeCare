import 'package:flutter/material.dart';
import '../services/vital_reading.dart';

class VitalQualityNotice extends StatelessWidget {
  const VitalQualityNotice({super.key, required this.readings});

  final List<VitalReading> readings;

  @override
  Widget build(BuildContext context) {
    final affected = readings.where((r) => r.hasQualityIssue).length;
    final unknown = readings.where((r) => r.hasUnreportedQuality).length;
    final unconfirmed = readings.any((r) => r.hasUnconfirmedSignal);
    if (affected == 0 && unknown == 0 && !unconfirmed) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        affected > 0
            ? 'Há medições indisponíveis ou inconclusivas.'
            : unconfirmed
            ? 'Há leituras com qualidade experimental não confirmada.'
            : 'Há medições sem informação de qualidade.',
        style: const TextStyle(color: Colors.red),
      ),
    );
  }
}
