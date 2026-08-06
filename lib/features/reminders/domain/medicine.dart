/// Model for a prescribed or over-the-counter medicine.
class Medicine {
  const Medicine({
    required this.id,
    required this.name,
    required this.dosage,
    this.frequency = 'Daily',
    this.morning = true,
    this.morningHour = 9,
    this.morningMinute = 0,
    this.afternoon = false,
    this.afternoonHour = 14,
    this.afternoonMinute = 0,
    this.night = false,
    this.nightHour = 21,
    this.nightMinute = 0,
    required this.startDate,
    this.endDate,
    this.purpose = '',
    this.isCompleted = false,
    this.sound = 'default',
    this.repeatType = 'daily',
    required this.createdAt,
  });

  final String id;
  final String name;
  final String dosage;
  final String frequency; // 'Daily', 'Twice Daily', 'Weekly', 'As needed'
  final bool morning;
  final int morningHour;
  final int morningMinute;
  final bool afternoon;
  final int afternoonHour;
  final int afternoonMinute;
  final bool night;
  final int nightHour;
  final int nightMinute;
  final DateTime startDate;
  final DateTime? endDate;
  final String purpose;
  final bool isCompleted;
  final String sound; // 'default', 'gentle', 'chime', 'urgent', 'classic'
  final String repeatType; // 'daily', 'weekly', 'custom'
  final DateTime createdAt;

  bool get isActive {
    if (isCompleted) return false;
    if (endDate == null) return true;
    final now = DateTime.now();
    final end = DateTime(endDate!.year, endDate!.month, endDate!.day, 23, 59, 59);
    return now.isBefore(end);
  }

  Medicine copyWith({
    String? name,
    String? dosage,
    String? frequency,
    bool? morning,
    int? morningHour,
    int? morningMinute,
    bool? afternoon,
    int? afternoonHour,
    int? afternoonMinute,
    bool? night,
    int? nightHour,
    int? nightMinute,
    DateTime? startDate,
    DateTime? endDate,
    bool clearEndDate = false,
    String? purpose,
    bool? isCompleted,
    String? sound,
    String? repeatType,
  }) {
    return Medicine(
      id: id,
      name: name ?? this.name,
      dosage: dosage ?? this.dosage,
      frequency: frequency ?? this.frequency,
      morning: morning ?? this.morning,
      morningHour: morningHour ?? this.morningHour,
      morningMinute: morningMinute ?? this.morningMinute,
      afternoon: afternoon ?? this.afternoon,
      afternoonHour: afternoonHour ?? this.afternoonHour,
      afternoonMinute: afternoonMinute ?? this.afternoonMinute,
      night: night ?? this.night,
      nightHour: nightHour ?? this.nightHour,
      nightMinute: nightMinute ?? this.nightMinute,
      startDate: startDate ?? this.startDate,
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
      purpose: purpose ?? this.purpose,
      isCompleted: isCompleted ?? this.isCompleted,
      sound: sound ?? this.sound,
      repeatType: repeatType ?? this.repeatType,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'dosage': dosage,
        'frequency': frequency,
        'morning': morning,
        'morningHour': morningHour,
        'morningMinute': morningMinute,
        'afternoon': afternoon,
        'afternoonHour': afternoonHour,
        'afternoonMinute': afternoonMinute,
        'night': night,
        'nightHour': nightHour,
        'nightMinute': nightMinute,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate?.toIso8601String(),
        'purpose': purpose,
        'isCompleted': isCompleted,
        'sound': sound,
        'repeatType': repeatType,
        'createdAt': createdAt.toIso8601String(),
      };

  static Medicine fromJson(Map<String, dynamic> j) => Medicine(
        id: (j['id'] as String?) ?? '${DateTime.now().microsecondsSinceEpoch}',
        name: (j['name'] as String?) ?? 'Medicine',
        dosage: (j['dosage'] as String?) ?? '',
        frequency: (j['frequency'] as String?) ?? 'Daily',
        morning: (j['morning'] as bool?) ?? true,
        morningHour: (j['morningHour'] as num?)?.toInt() ?? 9,
        morningMinute: (j['morningMinute'] as num?)?.toInt() ?? 0,
        afternoon: (j['afternoon'] as bool?) ?? false,
        afternoonHour: (j['afternoonHour'] as num?)?.toInt() ?? 14,
        afternoonMinute: (j['afternoonMinute'] as num?)?.toInt() ?? 0,
        night: (j['night'] as bool?) ?? false,
        nightHour: (j['nightHour'] as num?)?.toInt() ?? 21,
        nightMinute: (j['nightMinute'] as num?)?.toInt() ?? 0,
        startDate: DateTime.tryParse((j['startDate'] as String?) ?? '') ??
            DateTime.now(),
        endDate: j['endDate'] != null
            ? DateTime.tryParse(j['endDate'] as String)
            : null,
        purpose: (j['purpose'] as String?) ?? '',
        isCompleted: (j['isCompleted'] as bool?) ?? false,
        sound: (j['sound'] as String?) ?? 'default',
        repeatType: (j['repeatType'] as String?) ?? 'daily',
        createdAt: DateTime.tryParse((j['createdAt'] as String?) ?? '') ??
            DateTime.now(),
      );
}

/// A log entry indicating a dose was taken or missed at a specific date and time.
class DoseLog {
  const DoseLog({
    required this.id,
    required this.medicineId,
    required this.medicineName,
    required this.dosage,
    required this.scheduleSlot,
    required this.timestamp,
    required this.status,
  });

  final String id;
  final String medicineId;
  final String medicineName;
  final String dosage;
  final String scheduleSlot; // 'morning', 'afternoon', 'night', 'as_needed'
  final DateTime timestamp;
  final String status; // 'taken', 'missed', 'snoozed'

  bool get isTaken => status == 'taken';
  bool get isMissed => status == 'missed';

  DoseLog copyWith({
    String? status,
  }) =>
      DoseLog(
        id: id,
        medicineId: medicineId,
        medicineName: medicineName,
        dosage: dosage,
        scheduleSlot: scheduleSlot,
        timestamp: timestamp,
        status: status ?? this.status,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'medicineId': medicineId,
        'medicineName': medicineName,
        'dosage': dosage,
        'scheduleSlot': scheduleSlot,
        'timestamp': timestamp.toIso8601String(),
        'status': status,
      };

  static DoseLog fromJson(Map<String, dynamic> j) => DoseLog(
        id: (j['id'] as String?) ?? '${DateTime.now().microsecondsSinceEpoch}',
        medicineId: (j['medicineId'] as String?) ?? '',
        medicineName: (j['medicineName'] as String?) ?? 'Medicine',
        dosage: (j['dosage'] as String?) ?? '',
        scheduleSlot: (j['scheduleSlot'] as String?) ?? 'general',
        timestamp: DateTime.tryParse((j['timestamp'] as String?) ?? '') ??
            DateTime.now(),
        status: (j['status'] as String?) ?? 'taken',
      );
}
