/// Domain models for the patient's profile.
///
/// All plain Dart — no Flutter imports.
library;

enum AppLanguage {
  english('en', 'English'),
  tamil('ta', 'தமிழ்'),
  hindi('hi', 'हिन्दी');

  const AppLanguage(this.code, this.label);
  final String code;
  final String label;

  static AppLanguage fromCode(String code) {
    return AppLanguage.values.firstWhere(
      (l) => l.code == code,
      orElse: () => AppLanguage.english,
    );
  }
}

enum NotificationLevel {
  all('All'),
  important('Important only'),
  none('Off');

  const NotificationLevel(this.label);
  final String label;
}

class EmergencyContact {
  const EmergencyContact({
    required this.id,
    required this.name,
    required this.relation,
    required this.phone,
    this.isPrimary = false,
    this.whatsappApiKey,
  });
  final String id;
  final String name;
  final String relation;
  final String phone;
  final bool isPrimary;

  /// This contact's own CallMeBot API key, obtained by them opting in once
  /// (see `CallMeBotService` doc) — null means WhatsApp for this contact
  /// falls back to a pre-filled wa.me link the user taps to send instead of
  /// an automatic send.
  final String? whatsappApiKey;

  EmergencyContact copyWith({
    String? name,
    String? relation,
    String? phone,
    bool? isPrimary,
    String? whatsappApiKey,
    bool clearWhatsappApiKey = false,
  }) =>
      EmergencyContact(
        id: id,
        name: name ?? this.name,
        relation: relation ?? this.relation,
        phone: phone ?? this.phone,
        isPrimary: isPrimary ?? this.isPrimary,
        whatsappApiKey: clearWhatsappApiKey
            ? null
            : (whatsappApiKey ?? this.whatsappApiKey),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'relation': relation,
        'phone': phone,
        'isPrimary': isPrimary,
        'whatsappApiKey': whatsappApiKey,
      };

  static EmergencyContact fromJson(Map<String, dynamic> j) => EmergencyContact(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        relation: j['relation'] as String? ?? '',
        phone: j['phone'] as String? ?? '',
        isPrimary: (j['isPrimary'] as bool?) ?? false,
        whatsappApiKey: j['whatsappApiKey'] as String?,
      );
}

/// The patient's editable personal + medical identity block.
///
/// Persisted independently of the auth session so it survives logout/login.
/// [heightCm] and [weightKg] are stored as strings so the UI can round-trip
/// without lossy numeric conversion.
class PersonalDetails {
  const PersonalDetails({
    this.fullName = '',
    this.phone = '',
    this.email = '',
    this.dateOfBirth,
    this.gender = '',
    this.bloodGroup = '',
    this.heightCm = '',
    this.weightKg = '',
  });

  final String fullName;
  final String phone;
  final String email;
  final DateTime? dateOfBirth;
  final String gender;
  final String bloodGroup;
  final String heightCm;
  final String weightKg;

  static const empty = PersonalDetails();

  /// Age in whole years derived from [dateOfBirth], or null if unknown.
  int? get age {
    final dob = dateOfBirth;
    if (dob == null) return null;
    final now = DateTime.now();
    var years = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      years--;
    }
    return years < 0 ? null : years;
  }

  PersonalDetails copyWith({
    String? fullName,
    String? phone,
    String? email,
    DateTime? dateOfBirth,
    bool clearDateOfBirth = false,
    String? gender,
    String? bloodGroup,
    String? heightCm,
    String? weightKg,
  }) {
    return PersonalDetails(
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      dateOfBirth: clearDateOfBirth ? null : (dateOfBirth ?? this.dateOfBirth),
      gender: gender ?? this.gender,
      bloodGroup: bloodGroup ?? this.bloodGroup,
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
    );
  }

  Map<String, dynamic> toJson() => {
        'fullName': fullName,
        'phone': phone,
        'email': email,
        'dateOfBirth': dateOfBirth?.toIso8601String(),
        'gender': gender,
        'bloodGroup': bloodGroup,
        'heightCm': heightCm,
        'weightKg': weightKg,
      };

  static PersonalDetails fromJson(Map<String, dynamic> j) => PersonalDetails(
        fullName: (j['fullName'] as String?) ?? '',
        phone: (j['phone'] as String?) ?? '',
        email: (j['email'] as String?) ?? '',
        dateOfBirth: (j['dateOfBirth'] as String?) != null
            ? DateTime.tryParse(j['dateOfBirth'] as String)
            : null,
        gender: (j['gender'] as String?) ?? '',
        bloodGroup: (j['bloodGroup'] as String?) ?? '',
        heightCm: (j['heightCm'] as String?) ?? '',
        weightKg: (j['weightKg'] as String?) ?? '',
      );
}

class ProfileRecord {
  const ProfileRecord({
    required this.personal,
    required this.allergies,
    required this.conditions,
    required this.currentMedicines,
    required this.emergencyContacts,
    required this.biometricEnabled,
    required this.notifications,
    required this.language,
  });

  final PersonalDetails personal;
  final List<String> allergies;
  final List<String> conditions;
  final List<String> currentMedicines;
  final List<EmergencyContact> emergencyContacts;
  final bool biometricEnabled;
  final NotificationLevel notifications;
  final AppLanguage language;

  /// A clean starting state — no demo/placeholder data.
  static const initial = ProfileRecord(
    personal: PersonalDetails.empty,
    allergies: [],
    conditions: [],
    currentMedicines: [],
    emergencyContacts: [],
    biometricEnabled: false,
    notifications: NotificationLevel.all,
    language: AppLanguage.english,
  );

  ProfileRecord copyWith({
    PersonalDetails? personal,
    List<String>? allergies,
    List<String>? conditions,
    List<String>? currentMedicines,
    List<EmergencyContact>? emergencyContacts,
    bool? biometricEnabled,
    NotificationLevel? notifications,
    AppLanguage? language,
  }) {
    return ProfileRecord(
      personal: personal ?? this.personal,
      allergies: allergies ?? this.allergies,
      conditions: conditions ?? this.conditions,
      currentMedicines: currentMedicines ?? this.currentMedicines,
      emergencyContacts: emergencyContacts ?? this.emergencyContacts,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      notifications: notifications ?? this.notifications,
      language: language ?? this.language,
    );
  }
}
