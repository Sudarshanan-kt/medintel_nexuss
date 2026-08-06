/// Model representing an Emergency SOS trigger event.
class EmergencyEvent {
  const EmergencyEvent({
    required this.id,
    required this.timestamp,
    this.latitude,
    this.longitude,
    required this.primaryContactName,
    required this.primaryContactPhone,
    required this.message,
    required this.status, // 'triggered' | 'cancelled'
  });

  final String id;
  final DateTime timestamp;
  final double? latitude;
  final double? longitude;
  final String primaryContactName;
  final String primaryContactPhone;
  final String message;
  final String status;

  bool get hasLocation => latitude != null && longitude != null;

  String? get mapsUrl =>
      hasLocation ? 'https://maps.google.com/?q=$latitude,$longitude' : null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
        'primaryContactName': primaryContactName,
        'primaryContactPhone': primaryContactPhone,
        'message': message,
        'status': status,
      };

  static EmergencyEvent fromJson(Map<String, dynamic> j) => EmergencyEvent(
        id: (j['id'] as String?) ?? '${DateTime.now().microsecondsSinceEpoch}',
        timestamp: DateTime.tryParse((j['timestamp'] as String?) ?? '') ??
            DateTime.now(),
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
        primaryContactName: (j['primaryContactName'] as String?) ?? 'Contact',
        primaryContactPhone: (j['primaryContactPhone'] as String?) ?? '',
        message: (j['message'] as String?) ?? '',
        status: (j['status'] as String?) ?? 'triggered',
      );
}
