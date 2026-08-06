/// A scheduled daily medicine reminder.
class MedicineReminder {
  const MedicineReminder({
    required this.id,
    required this.medicine,
    required this.dosage,
    required this.hour,
    required this.minute,
    this.enabled = true,
  });

  final String id;
  final String medicine;
  final String dosage;
  final int hour; // 0–23
  final int minute; // 0–59
  final bool enabled;

  String get timeLabel {
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    final ampm = hour < 12 ? 'AM' : 'PM';
    final mm = minute.toString().padLeft(2, '0');
    return '$h12:$mm $ampm';
  }

  MedicineReminder copyWith({bool? enabled}) => MedicineReminder(
        id: id,
        medicine: medicine,
        dosage: dosage,
        hour: hour,
        minute: minute,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'medicine': medicine,
        'dosage': dosage,
        'hour': hour,
        'minute': minute,
        'enabled': enabled,
      };

  static MedicineReminder fromJson(Map<String, dynamic> j) => MedicineReminder(
        id: (j['id'] as String?) ?? '${DateTime.now().microsecondsSinceEpoch}',
        medicine: (j['medicine'] as String?) ?? 'Medicine',
        dosage: (j['dosage'] as String?) ?? '',
        hour: (j['hour'] as num?)?.toInt() ?? 9,
        minute: (j['minute'] as num?)?.toInt() ?? 0,
        enabled: (j['enabled'] as bool?) ?? true,
      );
}
