const Duration bogotaUtcOffset = Duration(hours: -5);

DateTime? reportDateTimeInBogota(dynamic value) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return null;

  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return null;

  final hasExplicitZone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(raw);
  if (!hasExplicitZone) return parsed;
  return parsed.toUtc().add(bogotaUtcOffset);
}

String formatReportDateTimeInBogota(dynamic value) {
  final date = reportDateTimeInBogota(value);
  if (date == null) {
    final raw = value?.toString() ?? '';
    return raw.isEmpty ? 'Fecha no disponible' : raw;
  }

  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final year = date.year.toString();
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$day/$month/$year, $hour:$minute';
}
