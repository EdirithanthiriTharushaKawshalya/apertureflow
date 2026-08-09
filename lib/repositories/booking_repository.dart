import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/calendar_event.dart';

/// Repository interface defining storage operations for calendar events.
/// Enables decoupling UI from the storage mechanism to support unit/widget testing.
abstract class BookingRepository {
  Stream<List<CalendarEvent>> streamBookings();
  /// Returns the newly created booking's id, so callers can key follow-up actions
  /// (e.g. scheduling a reminder notification) off of it.
  Future<String> addBooking(CalendarEvent event);
  Future<void> updateBooking(CalendarEvent event);
  Future<void> deleteBooking(String eventId);
}

/// Production implementation of [BookingRepository] backed by the device's local
/// storage (via [SharedPreferences]). No account, server, or network connection
/// is required — all bookings live only on this device.
class LocalBookingRepository implements BookingRepository {
  static const String _storageKey = 'apertureflow_bookings_v1';

  final StreamController<List<CalendarEvent>> _controller =
      StreamController<List<CalendarEvent>>.broadcast();
  List<CalendarEvent> _bookings = [];
  bool _loaded = false;

  /// Loads the persisted bookings from disk exactly once, lazily.
  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null) {
      final List<dynamic> decoded = jsonDecode(raw);
      _bookings = decoded
          .map((e) => CalendarEvent.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    _loaded = true;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_bookings.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, encoded);
  }

  @override
  Stream<List<CalendarEvent>> streamBookings() {
    _ensureLoaded().then((_) {
      if (!_controller.isClosed) {
        _controller.add(List.from(_bookings));
      }
    });
    return _controller.stream;
  }

  @override
  Future<String> addBooking(CalendarEvent event) async {
    await _ensureLoaded();
    final newEvent = CalendarEvent(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      date: event.date,
      type: event.type,
      reminderTime: event.reminderTime,
      description: event.description,
    );
    _bookings.add(newEvent);
    await _persist();
    _controller.add(List.from(_bookings));
    return newEvent.id;
  }

  @override
  Future<void> updateBooking(CalendarEvent event) async {
    await _ensureLoaded();
    final index = _bookings.indexWhere((e) => e.id == event.id);
    if (index != -1) {
      _bookings[index] = event;
      await _persist();
      _controller.add(List.from(_bookings));
    }
  }

  @override
  Future<void> deleteBooking(String eventId) async {
    await _ensureLoaded();
    _bookings.removeWhere((e) => e.id == eventId);
    await _persist();
    _controller.add(List.from(_bookings));
  }
}

/// InMemory mock repository used for previews, offline fallbacks, and widget testing.
class MockBookingRepository implements BookingRepository {
  final List<CalendarEvent> _bookings = [];
  final StreamController<List<CalendarEvent>> _controller =
      StreamController<List<CalendarEvent>>.broadcast();

  MockBookingRepository() {
    final now = DateTime.now();
    final year = now.year;
    final month = now.month;

    // Seed mock data
    _bookings.addAll([
      CalendarEvent(
        id: 'mock_shoot_1',
        date: DateTime(year, month, 5),
        type: 'Booked Shoot',
        description: 'Model portfolio shoot - Studio A',
      ),
      CalendarEvent(
        id: 'mock_rental_1',
        date: DateTime(year, month, 12),
        type: 'Equipment Rental',
        description: 'Sony A7R V + 24-70mm f/2.8 GM II',
      ),
      CalendarEvent(
        id: 'mock_rental_2',
        date: DateTime(year, month, 12),
        type: 'Equipment Rental',
        description: 'Profoto B10X Plus duo kit',
      ),
      CalendarEvent(
        id: 'mock_shoot_2',
        date: DateTime(year, month, 20),
        type: 'Booked Shoot',
        description: 'Outdoor wedding photoshoot - Botanical Gardens',
      ),
    ]);
    _controller.add(List.from(_bookings));
  }

  @override
  Stream<List<CalendarEvent>> streamBookings() {
    Timer(const Duration(milliseconds: 10), () {
      if (!_controller.isClosed) {
        _controller.add(List.from(_bookings));
      }
    });
    return _controller.stream;
  }

  @override
  Future<String> addBooking(CalendarEvent event) async {
    final newEvent = CalendarEvent(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: event.date,
      type: event.type,
      reminderTime: event.reminderTime,
      description: event.description,
    );
    _bookings.add(newEvent);
    _controller.add(List.from(_bookings));
    return newEvent.id;
  }

  @override
  Future<void> updateBooking(CalendarEvent event) async {
    final index = _bookings.indexWhere((e) => e.id == event.id);
    if (index != -1) {
      _bookings[index] = event;
      _controller.add(List.from(_bookings));
    }
  }

  @override
  Future<void> deleteBooking(String eventId) async {
    _bookings.removeWhere((e) => e.id == eventId);
    _controller.add(List.from(_bookings));
  }
}
