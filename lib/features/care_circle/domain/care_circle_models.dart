/// Domain models for the Family/Caregiver Circle feature.
library;

class CareCircleInvite {
  const CareCircleInvite({
    required this.id,
    required this.patientId,
    required this.patientDisplayName,
    required this.inviteCode,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
  });

  final String id;
  final String patientId;
  final String patientDisplayName;
  final String inviteCode;
  final String status; // pending / accepted / revoked
  final DateTime createdAt;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isPending => status == 'pending' && !isExpired;

  static CareCircleInvite fromRow(Map<String, dynamic> row) => CareCircleInvite(
        id: row['id'] as String,
        patientId: row['patient_id'] as String,
        patientDisplayName:
            (row['patient_display_name'] as String?) ?? 'Patient',
        inviteCode: row['invite_code'] as String,
        status: (row['status'] as String?) ?? 'pending',
        createdAt: DateTime.parse(row['created_at'] as String),
        expiresAt: DateTime.parse(row['expires_at'] as String),
      );
}

class CareCircleMember {
  const CareCircleMember({
    required this.id,
    required this.patientId,
    required this.patientDisplayName,
    required this.caregiverId,
    required this.caregiverDisplayName,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String patientId;
  final String patientDisplayName;
  final String caregiverId;
  final String caregiverDisplayName;
  final String status; // active / removed
  final DateTime createdAt;

  static CareCircleMember fromRow(Map<String, dynamic> row) => CareCircleMember(
        id: row['id'] as String,
        patientId: row['patient_id'] as String,
        patientDisplayName:
            (row['patient_display_name'] as String?) ?? 'Patient',
        caregiverId: row['caregiver_id'] as String,
        caregiverDisplayName:
            (row['caregiver_display_name'] as String?) ?? 'Caregiver',
        status: (row['status'] as String?) ?? 'active',
        createdAt: DateTime.parse(row['created_at'] as String),
      );
}

/// A task posted to a care circle — Lotsa Helping Hands' model: a concrete,
/// claimable ask ("ride to appointment Tuesday") rather than an open-ended
/// "help needed" post, so the circle sees exactly what's still outstanding.
class CareTask {
  const CareTask({
    required this.id,
    required this.patientId,
    required this.title,
    this.note,
    this.dueDate,
    required this.createdById,
    required this.createdByName,
    this.claimedById,
    this.claimedByName,
    required this.status,
    required this.createdAt,
  });

  final String id;

  /// Which circle this task belongs to — the patient's user id.
  final String patientId;

  final String title;
  final String? note;
  final DateTime? dueDate;

  final String createdById;
  final String createdByName;

  final String? claimedById;
  final String? claimedByName;

  /// open / claimed / done
  final String status;
  final DateTime createdAt;

  bool get isOpen => status == 'open';
  bool get isClaimed => status == 'claimed';
  bool get isDone => status == 'done';

  CareTask copyWith({
    String? claimedById,
    String? claimedByName,
    String? status,
  }) =>
      CareTask(
        id: id,
        patientId: patientId,
        title: title,
        note: note,
        dueDate: dueDate,
        createdById: createdById,
        createdByName: createdByName,
        claimedById: claimedById ?? this.claimedById,
        claimedByName: claimedByName ?? this.claimedByName,
        status: status ?? this.status,
        createdAt: createdAt,
      );

  static CareTask fromRow(Map<String, dynamic> row) => CareTask(
        id: row['id'] as String,
        patientId: row['patient_id'] as String,
        title: (row['title'] as String?) ?? '',
        note: row['note'] as String?,
        dueDate: row['due_date'] != null
            ? DateTime.tryParse(row['due_date'] as String)
            : null,
        createdById: row['created_by_id'] as String,
        createdByName: (row['created_by_name'] as String?) ?? 'Someone',
        claimedById: row['claimed_by_id'] as String?,
        claimedByName: row['claimed_by_name'] as String?,
        status: (row['status'] as String?) ?? 'open',
        createdAt: DateTime.parse(row['created_at'] as String),
      );
}
