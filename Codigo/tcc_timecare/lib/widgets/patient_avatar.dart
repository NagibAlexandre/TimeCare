import 'dart:convert';
import 'package:flutter/material.dart';

class PatientAvatar extends StatelessWidget {
  const PatientAvatar({super.key, required this.data, this.radius = 24});
  final Map<Object?, Object?> data;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final name = '${data['name'] ?? ''}'.trim();
    final initials = name
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => s.characters.first.toUpperCase())
        .join();
    final fallback = Center(
      child: initials.isEmpty
          ? const Icon(Icons.person_outline)
          : Text(initials, style: TextStyle(fontSize: radius * .65)),
    );
    Widget content = fallback;
    final encoded = data['photoBase64'];
    if (encoded is String && encoded.isNotEmpty) {
      try {
        content = Image.memory(
          base64Decode(encoded),
          fit: BoxFit.cover,
          width: radius * 2,
          height: radius * 2,
          errorBuilder: (_, error, stack) => fallback,
        );
      } on FormatException {
        // Invalid legacy photos still show a usable avatar.
      }
    }
    return Semantics(
      label: 'Foto de perfil',
      image: true,
      child: CircleAvatar(
        radius: radius,
        child: ClipOval(
          child: SizedBox.square(dimension: radius * 2, child: content),
        ),
      ),
    );
  }
}
