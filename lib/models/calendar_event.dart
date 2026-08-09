class CalendarEvent {
  final String id;
  final DateTime date;
  final String type; // 'Booked Shoot' or 'Equipment Rental'
  final DateTime? reminderTime; // Optional local-notification reminder moment
  final String? description; // Optional detailed description of the booking

  CalendarEvent({
    required this.id,
    required this.date,
    required this.type,
    this.reminderTime,
    this.description,
  });

  /// Converts event data to a JSON-serializable map for on-device storage.
  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'type': type,
        'reminderTime': reminderTime?.toIso8601String(),
        'description': description,
      };

  /// Factory method to reconstruct an event from a JSON map read from local storage.
  factory CalendarEvent.fromJson(Map<String, dynamic> json) {
    final reminderTimeRaw = json['reminderTime'] as String?;
    return CalendarEvent(
      id: json['id'] as String,
      date: DateTime.parse(json['date'] as String),
      type: json['type'] as String,
      reminderTime: reminderTimeRaw != null ? DateTime.parse(reminderTimeRaw) : null,
      description: json['description'] as String?,
    );
  }
}
