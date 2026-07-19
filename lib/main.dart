import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';
import 'notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase using platform configurations
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await NotificationService.instance.init();
  await NotificationService.instance.requestPermissions();

  runApp(ApertureFlowApp(repository: FirestoreBookingRepository()));
}

/// The root widget of the ApertureFlow Availability and Rental Management application.
/// Configures a premium light-themed UI tailored for professional photographers.
class ApertureFlowApp extends StatelessWidget {
  final BookingRepository repository;

  const ApertureFlowApp({super.key, required this.repository});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ApertureFlow',
      debugShowCheckedModeBanner: false,
      // Premium Dashboard layout light theme configuration (Neumorphic styling)
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFEBF1F5), // Light blue-grey background
        primaryColor: const Color(0xFF0F172A), // Slate Dark Accent
        fontFamily: GoogleFonts.quicksand().fontFamily,
        textTheme: GoogleFonts.quicksandTextTheme(ThemeData.light().textTheme),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F172A),
          brightness: Brightness.light,
          primary: const Color(0xFF0F172A),
          secondary: const Color(0xFF0F172A),
          surface: Colors.white,
          background: const Color(0xFFEBF1F5),
          error: Colors.redAccent,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
          titleTextStyle: GoogleFonts.quicksand(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.0,
            color: const Color(0xFF0F172A),
          ),
        ),
      ),
      home: HomeScreen(repository: repository),
    );
  }
}

/// Repository interface defining database operations for calendar events.
/// Enables decoupling UI from Firebase to support unit/widget testing.
abstract class BookingRepository {
  Stream<List<CalendarEvent>> streamBookings();
  /// Returns the newly created booking's id, so callers can key follow-up actions
  /// (e.g. scheduling a reminder notification) off of it.
  Future<String> addBooking(CalendarEvent event);
  Future<void> updateBooking(CalendarEvent event);
  Future<void> deleteBooking(String eventId);
}

/// Production implementation of [BookingRepository] using Firebase Cloud Firestore.
class FirestoreBookingRepository implements BookingRepository {
  final CollectionReference _bookingsRef =
      FirebaseFirestore.instance.collection('bookings');

  @override
  Stream<List<CalendarEvent>> streamBookings() {
    return _bookingsRef.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) {
          return CalendarEvent(id: doc.id, date: DateTime.now(), type: 'Booked Shoot');
        }
        return CalendarEvent.fromFirestore(doc.id, data);
      }).toList();
    });
  }

  @override
  Future<String> addBooking(CalendarEvent event) async {
    final docRef = await _bookingsRef.add(event.toFirestore());
    return docRef.id;
  }

  @override
  Future<void> updateBooking(CalendarEvent event) async {
    await _bookingsRef.doc(event.id).update(event.toFirestore());
  }

  @override
  Future<void> deleteBooking(String eventId) async {
    await _bookingsRef.doc(eventId).delete();
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
      ),
      CalendarEvent(
        id: 'mock_rental_1',
        date: DateTime(year, month, 12),
        type: 'Equipment Rental',
      ),
      CalendarEvent(
        id: 'mock_rental_2',
        date: DateTime(year, month, 12),
        type: 'Equipment Rental',
      ),
      CalendarEvent(
        id: 'mock_shoot_2',
        date: DateTime(year, month, 20),
        type: 'Booked Shoot',
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

/// Calendar event model class containing basic identifier, event date,
/// and type classification.
class CalendarEvent {
  final String id;
  final DateTime date;
  final String type; // 'Booked Shoot' or 'Equipment Rental'
  final DateTime? reminderTime; // Optional local-notification reminder moment

  CalendarEvent({
    required this.id,
    required this.date,
    required this.type,
    this.reminderTime,
  });

  /// Convert event data to a Map format compatible with Cloud Firestore.
  Map<String, dynamic> toFirestore() => {
        'date': Timestamp.fromDate(date),
        'type': type,
        'reminderTime': reminderTime != null ? Timestamp.fromDate(reminderTime!) : null,
      };

  /// Factory method to construct an event from Cloud Firestore document maps.
  factory CalendarEvent.fromFirestore(String docId, Map<String, dynamic> data) {
    final Timestamp timestamp = data['date'] as Timestamp;
    final Timestamp? reminderTimestamp = data['reminderTime'] as Timestamp?;
    return CalendarEvent(
      id: docId,
      date: timestamp.toDate(),
      type: data['type'] as String,
      reminderTime: reminderTimestamp?.toDate(),
    );
  }
}

/// Main application screen managing calendar displays, intake bottom sheets,
/// local storage updates, and clipboard share operations.
class HomeScreen extends StatefulWidget {
  final BookingRepository repository;

  const HomeScreen({super.key, required this.repository});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Calendar tracking dates
  late DateTime _focusedDay;
  late DateTime _selectedDay;

  // State events dictionary mapped by normalized Local DateTime (Midnight offset)
  Map<DateTime, List<CalendarEvent>> _events = {};

  late Stream<List<CalendarEvent>> _bookingsStream;
  bool _isSeeding = false;

  @override
  void initState() {
    super.initState();
    final today = _normalizeDate(DateTime.now());
    _focusedDay = today;
    _selectedDay = today;
    _bookingsStream = widget.repository.streamBookings();
  }

  /// Truncates the time component of a [DateTime] to avoid timezone mismatch when mapping events.
  DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  /// Renders the application logo mark as a clean dark icon (no image asset).
  Widget _buildLogo({double size = 26}) {
    return Icon(Icons.calendar_today_rounded, size: size, color: const Color(0xFF0F172A));
  }

  /// Branded loading screen shown while the initial booking data streams in,
  /// styled to match the rest of the dashboard (white card, soft shadow, logo badge).
  Widget _buildLoadingScreen() {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: _buildSoftShadow(),
              ),
              child: _buildLogo(size: 40),
            ),
            const SizedBox(height: 24),
            const Text(
              'APERTUREFLOW',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.0,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 28),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0F172A)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Computes soft neumorphic style layout drop shadows for visual card elevations.
  List<BoxShadow> _buildSoftShadow() {
    return [
      BoxShadow(
        color: const Color(0xFF1E293B).withOpacity(0.04), // Soft deep slate shadow
        blurRadius: 24,
        offset: const Offset(0, 8),
      ),
    ];
  }

  /// Calculates available remaining calendar days in the currently viewed month,
  /// formats as text, copies to system clipboard, and launches notification indicator.
  Future<void> _copyFreeDatesToClipboard() async {
    final today = _normalizeDate(DateTime.now());
    final focusedYear = _focusedDay.year;
    final focusedMonth = _focusedDay.month;

    // Find the last day of the currently focused month
    final lastDayOfMonth = DateTime(focusedYear, focusedMonth + 1, 0);

    final List<DateTime> freeDays = [];

    // Scan all days in the currently focused month
    for (int day = 1; day <= lastDayOfMonth.day; day++) {
      final currentDay = _normalizeDate(DateTime(focusedYear, focusedMonth, day));

      // Filter out past days
      if (currentDay.isBefore(today)) {
        continue;
      }

      final dayEvents = _events[currentDay] ?? [];
      if (dayEvents.isEmpty) {
        freeDays.add(currentDay);
      }
    }

    final monthName = DateFormat('MMMM').format(DateTime(focusedYear, focusedMonth));

    String textToCopy;
    if (freeDays.isEmpty) {
      textToCopy = "No free dates remaining in $monthName $focusedYear.";
    } else {
      final formattedDates = freeDays.map((d) => DateFormat('MMMM d').format(d)).join(', ');
      textToCopy = "My free dates for $monthName: $formattedDates";
    }

    await Clipboard.setData(ClipboardData(text: textToCopy));

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            _buildLogo(size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                freeDays.isEmpty
                    ? 'No remaining free dates to copy.'
                    : 'Free dates copied to clipboard!',
                style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFEBEBEB), width: 1),
        ),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Calculates total free days remaining in the focused month.
  int _getFreeDaysCount() {
    final year = _focusedDay.year;
    final month = _focusedDay.month;
    final lastDay = DateTime(year, month + 1, 0).day;
    int count = 0;
    for (int day = 1; day <= lastDay; day++) {
      final date = _normalizeDate(DateTime(year, month, day));
      if ((_events[date] ?? []).isEmpty) {
        count++;
      }
    }
    return count;
  }

  /// Calculates total count of events in focused month matching selected [type].
  int _getEventCountByType(String type) {
    final year = _focusedDay.year;
    final month = _focusedDay.month;
    final lastDay = DateTime(year, month + 1, 0).day;
    int count = 0;
    for (int day = 1; day <= lastDay; day++) {
      final date = _normalizeDate(DateTime(year, month, day));
      final events = _events[date] ?? [];
      count += events.where((e) => e.type == type).length;
    }
    return count;
  }

  /// Triggers automated seeding in production database when snapshots report empty setup.
  Future<void> _seedFirestore() async {
    try {
      final now = DateTime.now();
      final year = now.year;
      final month = now.month;

      final day5 = _normalizeDate(DateTime(year, month, 5));
      final day12 = _normalizeDate(DateTime(year, month, 12));
      final day20 = _normalizeDate(DateTime(year, month, 20));

      await widget.repository.addBooking(CalendarEvent(
        id: '',
        date: day5,
        type: 'Booked Shoot',
      ));

      await widget.repository.addBooking(CalendarEvent(
        id: '',
        date: day12,
        type: 'Equipment Rental',
      ));

      await widget.repository.addBooking(CalendarEvent(
        id: '',
        date: day12,
        type: 'Equipment Rental',
      ));

      await widget.repository.addBooking(CalendarEvent(
        id: '',
        date: day20,
        type: 'Booked Shoot',
      ));
    } catch (e) {
      debugPrint("Error seeding Firestore: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isSeeding = false;
        });
      }
    }
  }

  /// Triggers dialog confirmations prior to discarding scheduled system entries.
  Future<void> _deleteEvent(CalendarEvent event) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Booking?', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to delete this ${event.type.toLowerCase()} booking?',
          style: const TextStyle(color: Color(0xFF484848)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('DELETE', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await widget.repository.deleteBooking(event.id);
        await NotificationService.instance.cancelReminder(event.id);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF43F5E).withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_rounded, color: Color(0xFFE11D48), size: 16),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${event.type} removed from your calendar.',
                    style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.white,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFEBEBEB), width: 1),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete booking: $e'),
            backgroundColor: Colors.redAccent.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  /// Collects every booking with a future reminder set, soonest first.
  List<CalendarEvent> _getUpcomingReminders() {
    final now = DateTime.now();
    final reminders = <CalendarEvent>[];
    for (final dayEvents in _events.values) {
      for (final event in dayEvents) {
        if (event.reminderTime != null && event.reminderTime!.isAfter(now)) {
          reminders.add(event);
        }
      }
    }
    reminders.sort((a, b) => a.reminderTime!.compareTo(b.reminderTime!));
    return reminders;
  }

  /// Opens a bottom sheet listing every upcoming booking reminder.
  void _openNotificationsPanel() {
    final reminders = _getUpcomingReminders();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Notifications',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.black45, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: reminders.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A).withOpacity(0.04),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.notifications_none_rounded, color: Color(0xFF0F172A), size: 32),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No Upcoming Reminders',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Reminders you set on bookings will show up here.',
                              style: TextStyle(fontSize: 12, color: Color(0xFF767676), fontWeight: FontWeight.w500),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: reminders.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final event = reminders[index];
                          final isShoot = event.type == 'Booked Shoot';
                          final accent = isShoot ? const Color(0xFFF43F5E) : const Color(0xFFF59E0B);
                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFEBEBEB), width: 1.0),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: accent.withOpacity(0.10),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(Icons.notifications_active_outlined, color: accent, size: 18),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        event.type,
                                        style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.bold),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        NotificationService.formatReminder(event.reminderTime!),
                                        style: const TextStyle(color: Color(0xFF767676), fontSize: 11, fontWeight: FontWeight.w700),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Bell icon button used in both the desktop header and mobile app bar,
  /// showing a badge count of upcoming reminders.
  Widget _buildNotificationBell({double size = 42, double iconSize = 20}) {
    final count = _getUpcomingReminders().length;
    return GestureDetector(
      onTap: _openNotificationsPanel,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(size * 0.31),
          boxShadow: _buildSoftShadow(),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Icon(Icons.notifications_outlined, color: const Color(0xFF0F172A), size: iconSize),
            if (count > 0)
              Positioned(
                top: size * 0.14,
                right: size * 0.14,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF43F5E),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Text(
                    count > 9 ? '9+' : '$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900, height: 1.0),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Triggers a bottom sheet input frame for new event submission (iOS row layout).
  /// Pass [editingEvent] to pre-fill the form and update that booking instead of creating a new one.
  Future<void> _openAddEventForm({CalendarEvent? editingEvent}) async {
    final bool isEditing = editingEvent != null;

    final CalendarEvent? resultEvent = await showModalBottomSheet<CalendarEvent>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        DateTime formDate = editingEvent?.date ?? _selectedDay;
        String selectedType = editingEvent?.type ?? 'Booked Shoot';
        final formKey = GlobalKey<FormState>();
        String? localError;
        DateTime? reminderTime = editingEvent?.reminderTime;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            final formattedFormDate = DateFormat('EEEE, MMMM d, yyyy').format(formDate);

            // Use standard Padding since MediaQuery.of(context).viewInsets.bottom
            // is already animated frame-by-frame by the OS / Flutter framework.
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                      offset: Offset(0, -2),
                    )
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            color: Colors.black12,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            isEditing ? 'Edit Booking' : 'New Booking',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.black45, size: 20),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // iOS Row Layout Container (Grouped Card style from Image 2)
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F7F7),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFEBEBEB), width: 1.0),
                        ),
                        child: Column(
                          children: [
                            // ROW 1: Date Selection Row
                            InkWell(
                              onTap: () async {
                                final DateTime? picked = await showDatePicker(
                                  context: context,
                                  initialDate: formDate,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2030),
                                  builder: (context, child) {
                                    return Theme(
                                      data: Theme.of(context).copyWith(
                                        colorScheme: const ColorScheme.light(
                                          primary: Color(0xFF0F172A),
                                          onPrimary: Colors.white,
                                          surface: Colors.white,
                                          onSurface: Color(0xFF0F172A),
                                        ),
                                      ),
                                      child: child!,
                                    );
                                  },
                                );
                                if (picked != null) {
                                  setSheetState(() {
                                    formDate = picked;
                                    localError = null;
                                  });
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                child: Row(
                                  children: [
                                    const Icon(Icons.calendar_today_outlined, color: Color(0xFF484848), size: 18),
                                    const SizedBox(width: 12),
                                    const Text(
                                      'Date',
                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF484848)),
                                    ),
                                    const Spacer(),
                                    Text(
                                      formattedFormDate,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.chevron_right, color: Colors.black26, size: 16),
                                  ],
                                ),
                              ),
                            ),
                            
                            const Divider(height: 1, color: Color(0xFFEBEBEB), indent: 46),
                            
                            // ROW 2: Type Selection Dropdown Row
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Row(
                                children: [
                                  const Icon(Icons.category_outlined, color: Color(0xFF484848), size: 18),
                                  const SizedBox(width: 12),
                                  const Text(
                                    'Type',
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF484848)),
                                  ),
                                  const Spacer(),
                                  DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: selectedType,
                                      dropdownColor: Colors.white,
                                      alignment: Alignment.centerRight,
                                      icon: const Icon(Icons.arrow_drop_down, color: Colors.black45),
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                      items: const [
                                        DropdownMenuItem(
                                          value: 'Booked Shoot',
                                          child: Text('Booked Shoot'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'Equipment Rental',
                                          child: Text('Equipment Rental'),
                                        ),
                                      ],
                                      onChanged: (val) {
                                        if (val != null) {
                                          setSheetState(() {
                                            selectedType = val;
                                            localError = null;
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1, color: Color(0xFFEBEBEB), indent: 46),

                            // ROW 4: Reminder Row
                            InkWell(
                              onTap: () async {
                                final option = await showDialog<String>(
                                  context: context,
                                  builder: (dialogContext) => AlertDialog(
                                    backgroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    title: const Text(
                                      'Set Reminder',
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                                    ),
                                    contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ListTile(
                                          leading: const Icon(Icons.notifications_off_outlined, color: Color(0xFF484848)),
                                          title: const Text('No Reminder', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                          onTap: () => Navigator.pop(dialogContext, 'off'),
                                        ),
                                        ListTile(
                                          leading: const Icon(Icons.event_outlined, color: Color(0xFF484848)),
                                          title: const Text('1 Day Before · 9:00 AM', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                          onTap: () => Navigator.pop(dialogContext, 'dayBefore'),
                                        ),
                                        ListTile(
                                          leading: const Icon(Icons.wb_sunny_outlined, color: Color(0xFF484848)),
                                          title: const Text('Morning Of · 8:00 AM', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                          onTap: () => Navigator.pop(dialogContext, 'sameDay'),
                                        ),
                                        ListTile(
                                          leading: const Icon(Icons.edit_calendar_outlined, color: Color(0xFF484848)),
                                          title: const Text('Custom Date & Time', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                          onTap: () => Navigator.pop(dialogContext, 'custom'),
                                        ),
                                      ],
                                    ),
                                  ),
                                );

                                if (option == null) return;

                                if (option == 'off') {
                                  setSheetState(() => reminderTime = null);
                                } else if (option == 'dayBefore') {
                                  final day = formDate.subtract(const Duration(days: 1));
                                  setSheetState(() => reminderTime = DateTime(day.year, day.month, day.day, 9, 0));
                                } else if (option == 'sameDay') {
                                  setSheetState(
                                      () => reminderTime = DateTime(formDate.year, formDate.month, formDate.day, 8, 0));
                                } else if (option == 'custom') {
                                  if (!context.mounted) return;
                                  final pickedDate = await showDatePicker(
                                    context: context,
                                    initialDate: reminderTime ?? formDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2030),
                                    builder: (context, child) {
                                      return Theme(
                                        data: Theme.of(context).copyWith(
                                          colorScheme: const ColorScheme.light(
                                            primary: Color(0xFF0F172A),
                                            onPrimary: Colors.white,
                                            surface: Colors.white,
                                            onSurface: Color(0xFF0F172A),
                                          ),
                                        ),
                                        child: child!,
                                      );
                                    },
                                  );
                                  if (pickedDate == null || !context.mounted) return;

                                  final pickedTime = await showTimePicker(
                                    context: context,
                                    initialTime: reminderTime != null
                                        ? TimeOfDay(hour: reminderTime!.hour, minute: reminderTime!.minute)
                                        : const TimeOfDay(hour: 9, minute: 0),
                                    builder: (context, child) {
                                      return Theme(
                                        data: Theme.of(context).copyWith(
                                          colorScheme: const ColorScheme.light(
                                            primary: Color(0xFF0F172A),
                                            onPrimary: Colors.white,
                                            surface: Colors.white,
                                            onSurface: Color(0xFF0F172A),
                                          ),
                                        ),
                                        child: child!,
                                      );
                                    },
                                  );
                                  if (pickedTime == null) return;

                                  setSheetState(() {
                                    reminderTime = DateTime(
                                      pickedDate.year,
                                      pickedDate.month,
                                      pickedDate.day,
                                      pickedTime.hour,
                                      pickedTime.minute,
                                    );
                                  });
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                child: Row(
                                  children: [
                                    const Icon(Icons.notifications_outlined, color: Color(0xFF484848), size: 18),
                                    const SizedBox(width: 12),
                                    const Text(
                                      'Reminder',
                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF484848)),
                                    ),
                                    const Spacer(),
                                    Text(
                                      reminderTime != null ? NotificationService.formatReminder(reminderTime!) : 'Off',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: reminderTime != null ? const Color(0xFF0F172A) : Colors.black38,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.chevron_right, color: Colors.black26, size: 16),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      if (localError != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          localError!,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ],

                      const SizedBox(height: 24),

                      // Pill-shaped action button at bottom
                      ElevatedButton(
                        onPressed: () {
                          if (formKey.currentState!.validate()) {
                            final normDate = _normalizeDate(formDate);

                            // Validating against Booked Shoot double bookings on target date
                            if (selectedType == 'Booked Shoot') {
                              final existingEvents = _events[normDate] ?? [];
                              final hasShoot = existingEvents.any((e) =>
                                  e.type == 'Booked Shoot' && e.id != editingEvent?.id);
                              if (hasShoot) {
                                setSheetState(() {
                                  localError = 'A Booked Shoot is already scheduled on this day.';
                                });
                                return;
                              }
                            }

                            final event = CalendarEvent(
                              id: editingEvent?.id ?? '',
                              date: normDate,
                              type: selectedType,
                              reminderTime: reminderTime,
                            );
                            Navigator.pop(context, event);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F172A), // Solid dark slate
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28), // Pill
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          isEditing ? 'Save Changes' : 'Save Booking',
                          style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.0, fontSize: 14),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              ),
            );
          },
        );
      },
    );

    if (resultEvent != null) {
      try {
        String bookingId = resultEvent.id;
        if (isEditing) {
          await widget.repository.updateBooking(resultEvent);
        } else {
          bookingId = await widget.repository.addBooking(resultEvent);
        }

        if (resultEvent.reminderTime != null) {
          await NotificationService.instance.scheduleReminder(
            bookingId: bookingId,
            reminderTime: resultEvent.reminderTime!,
            eventType: resultEvent.type,
            eventDate: DateFormat('EEEE, MMMM d').format(resultEvent.date),
          );
        } else {
          await NotificationService.instance.cancelReminder(bookingId);
        }

        setState(() {
          _selectedDay = resultEvent.date;
          _focusedDay = resultEvent.date;
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                _buildLogo(size: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isEditing
                        ? '${resultEvent.type} updated successfully!'
                        : '${resultEvent.type} added successfully to Cloud Firestore!',
                    style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.white,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFEBEBEB), width: 1),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save to Firestore: $e'),
            backgroundColor: Colors.redAccent.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Renders individual calendar cells depending on date logic status.
  Widget _buildCalendarCell(DateTime day, {required bool isSelected, required bool isToday, required bool isOutside}) {
    final normalized = _normalizeDate(day);
    final dayEvents = _events[normalized] ?? [];

    // Decide color mapping. Booked Shoot takes top color precedence.
    String status = 'free';
    if (dayEvents.any((e) => e.type == 'Booked Shoot')) {
      status = 'shoot';
    } else if (dayEvents.isNotEmpty) {
      status = 'rental';
    }

    // Default styles for normal (free) days
    Color? cellColor;
    Color textColor = const Color(0xFF0F172A); // Dark charcoal for normal numbers
    BoxBorder? cellBorder;

    if (isOutside) {
      textColor = Colors.black26; // Faded out for adjacent month days
    }

    if (status == 'shoot') {
      cellColor = const Color(0xFFF43F5E); // Softer premium crimson (Rose)
      textColor = Colors.white;
    } else if (status == 'rental') {
      cellColor = const Color(0xFFF59E0B); // Softer premium amber (Yellow-orange)
      textColor = Colors.white;
    } else {
      // Free day selection (Solid dark slate circle Airbnb style)
      if (isSelected) {
        cellColor = const Color(0xFF0F172A);
        textColor = Colors.white;
      }
    }

    // Border highlights for selected booked days
    if (isSelected && status != 'free') {
      cellBorder = Border.all(color: const Color(0xFF0F172A), width: 2.5);
    } else if (isToday && !isSelected) {
      cellBorder = Border.all(color: const Color(0xFF0F172A).withOpacity(0.3), width: 1.5);
    }

    return Container(
      margin: const EdgeInsets.all(2.0), // Tight margin so circles fill the larger cell
      decoration: BoxDecoration(
        color: cellColor,
        shape: BoxShape.circle,
        border: cellBorder,
        boxShadow: cellColor != null && !isOutside
            ? [
                BoxShadow(
                  color: cellColor.withOpacity(0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                )
              ]
            : null,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            '${day.day}',
            style: TextStyle(
              color: textColor,
              fontWeight: isSelected || isToday || status != 'free' ? FontWeight.w900 : FontWeight.bold,
              fontSize: 16,
            ),
          ),
          if (isToday && cellColor == null)
            Positioned(
              bottom: 6,
              child: Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  color: Color(0xFF0F172A), // Dark dot for today on normal dates
                  shape: BoxShape.circle,
                ),
              ),
            )
          else if (isToday && cellColor != null)
            Positioned(
              bottom: 6,
              child: Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  color: Colors.white, // White dot for today on colored selections
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Builds month summary stats.
  Widget _buildStatsRow() {
    final freeCount = _getFreeDaysCount();
    final shootCount = _getEventCountByType('Booked Shoot');
    final rentalCount = _getEventCountByType('Equipment Rental');
    final daysInMonth = DateTime(_focusedDay.year, _focusedDay.month + 1, 0).day;

    final monthName = DateFormat('MMMM').format(_focusedDay).toUpperCase();
    final formattedDate = DateFormat('MMMM d, yyyy').format(DateTime.now());

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4.0, bottom: 10.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$monthName SUMMARY',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: Color(0xFF0F172A),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_today_rounded, size: 11, color: Color(0xFF767676)),
                    const SizedBox(width: 5),
                    Text(
                      formattedDate,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF767676),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Row(
            children: [
              _buildStatCard('FREE DAYS', '$freeCount', freeCount, daysInMonth, const Color(0xFF0F172A)),
              const SizedBox(width: 8),
              _buildStatCard('SHOOTS', '$shootCount', shootCount, daysInMonth, const Color(0xFFF43F5E)),
              const SizedBox(width: 8),
              _buildStatCard('RENTALS', '$rentalCount', rentalCount, daysInMonth, const Color(0xFFF59E0B)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, int count, int maxValue, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: _buildSoftShadow(),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color.withOpacity(0.85),
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            _buildTickBars(count, maxValue, color),
          ],
        ),
      ),
    );
  }

  /// Small decorative tick-bar indicator (sparkline style) beneath each stat value,
  /// filling proportionally to how much of the month the count represents.
  Widget _buildTickBars(int count, int maxValue, Color color) {
    const totalTicks = 10;
    const heights = [7.0, 11.0, 15.0, 9.0, 13.0, 16.0, 8.0, 12.0, 14.0, 10.0];
    final filledTicks = maxValue > 0
        ? ((count / maxValue) * totalTicks).clamp(0, totalTicks).round()
        : 0;

    return SizedBox(
      height: 16,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(totalTicks, (i) {
          final isFilled = i < filledTicks;
          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.2),
              height: heights[i],
              decoration: BoxDecoration(
                color: isFilled ? color : color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  /// Builds legend indicators mapping color status rules.
  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildLegendItem('SHOOT', const Color(0xFFF43F5E)),
          const SizedBox(width: 24),
          _buildLegendItem('RENTAL', const Color(0xFFF59E0B)),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF484848),
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }

  /// Renders detailed event cards or free state placeholders as slivers (iOS list cards).
  Widget _buildSliverEventList() {
    final normDate = _normalizeDate(_selectedDay);
    final dayEvents = _events[normDate] ?? [];

    if (dayEvents.isEmpty) {
      return SliverToBoxAdapter(
        child: _buildEmptyBookingsPlaceholder(),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final event = dayEvents[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: _buildBookingItemRow(event),
          );
        },
        childCount: dayEvents.length,
      ),
    );
  }

  /// Builds a placeholder when day has no bookings.
  Widget _buildEmptyBookingsPlaceholder() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEBEBEB), width: 1.0),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withOpacity(0.04),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.event_available_outlined,
              color: Color(0xFF0F172A),
              size: 32,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Available Day',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You have no scheduled bookings or equipment rentals on this day.',
            style: const TextStyle(
              color: Color(0xFF767676),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _openAddEventForm,
            icon: const Icon(Icons.add, size: 16),
            label: const Text(
              'Add Booking',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF0F172A),
              side: const BorderSide(color: Color(0xFFEBEBEB)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds a booking element card reusable row, styled to match the rest of
  /// the dashboard: white card, neutral soft shadow, flat tinted icon circle.
  /// Tapping the card (or the edit icon) opens it pre-filled for editing.
  Widget _buildBookingItemRow(CalendarEvent event) {
    final isShoot = event.type == 'Booked Shoot';
    final accent = isShoot ? const Color(0xFFF43F5E) : const Color(0xFFF59E0B);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _openAddEventForm(editingEvent: event),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: _buildSoftShadow(),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isShoot ? Icons.photo_camera_outlined : Icons.handyman_outlined,
                  color: accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.type,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 14.0,
                        fontWeight: FontWeight.bold,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, color: Colors.black26, size: 20),
                splashRadius: 20,
                color: Colors.white,
                elevation: 4,
                shadowColor: const Color(0xFF1E293B).withOpacity(0.15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: Color(0xFFEBEBEB), width: 1.0),
                ),
                onSelected: (value) {
                  if (value == 'edit') {
                    _openAddEventForm(editingEvent: event);
                  } else if (value == 'delete') {
                    _deleteEvent(event);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: const [
                        Icon(Icons.edit_outlined, color: Color(0xFF0F172A), size: 18),
                        SizedBox(width: 12),
                        Text(
                          'Edit',
                          style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: const [
                        Icon(Icons.delete_outline_rounded, color: Color(0xFFE11D48), size: 18),
                        SizedBox(width: 12),
                        Text(
                          'Delete',
                          style: TextStyle(color: Color(0xFFE11D48), fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds a clean desktop title header pane
  Widget _buildHeaderBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: _buildSoftShadow(),
            ),
            child: _buildLogo(size: 26),
          ),
          const SizedBox(width: 14),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'APERTUREFLOW',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: Color(0xFF0F172A),
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Availability & Rental Dashboard',
                style: TextStyle(fontSize: 12, color: Colors.black45, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const Spacer(),
          _buildNotificationBell(),
        ],
      ),
    );
  }

  /// Left vertical navigation bar — modernized with a gradient logo badge and
  /// an elevated gradient pill for the active nav item.
  Widget _buildSidebar() {
    return Container(
      width: 84,
      color: Colors.white,
      child: Column(
        children: [
          const SizedBox(height: 28),
          Container(
            width: 46,
            height: 46,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: _buildSoftShadow(),
            ),
            child: _buildLogo(size: 26),
          ),
          const SizedBox(height: 48),
          _buildSidebarItem(Icons.grid_view_rounded, true),
          _buildSidebarItem(Icons.calendar_month_rounded, false),
          _buildSidebarItem(Icons.handyman_outlined, false),
          _buildSidebarItem(Icons.settings_outlined, false),
          const Spacer(),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(IconData icon, bool isActive) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        gradient: isActive
            ? const LinearGradient(
                colors: [Color(0xFF0F172A), Color(0xFF334155)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        borderRadius: BorderRadius.circular(14),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: const Color(0xFF0F172A).withOpacity(0.28),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ]
            : null,
      ),
      child: Icon(
        icon,
        color: isActive ? Colors.white : Colors.black38,
        size: 22,
      ),
    );
  }

  /// Builds a structured desktop booking cards details panel (Right flex Column)
  Widget _buildDesktopBookingsPane(String formattedSelectedDate) {
    final normDate = _normalizeDate(_selectedDay);
    final dayEvents = _events[normDate] ?? [];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: _buildSoftShadow(),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.bookmarks_outlined, color: Colors.black45, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'BOOKINGS: $formattedSelectedDate',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: dayEvents.isEmpty
                ? Center(
                    child: SingleChildScrollView(
                      child: _buildEmptyBookingsPlaceholder(),
                    ),
                  )
                : ListView.builder(
                    itemCount: dayEvents.length,
                    itemBuilder: (context, index) {
                      final event = dayEvents[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: _buildBookingItemRow(event),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// Encapsulates copy free dates action button widget
  Widget _buildCopyButton() {
    return Align(
      alignment: Alignment.center,
      child: ElevatedButton.icon(
        onPressed: _copyFreeDatesToClipboard,
        icon: const Icon(Icons.copy_rounded, size: 15),
        label: const Text(
          'COPY FREE DATES',
          style: TextStyle(letterSpacing: 1.0, fontWeight: FontWeight.w800, fontSize: 11),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF0F172A),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFEBEBEB), width: 1.0),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  /// Encapsulates core calendar component
  Widget _buildCalendarWidget() {
    return TableCalendar(
      firstDay: DateTime.utc(2020, 1, 1),
      lastDay: DateTime.utc(2030, 12, 31),
      focusedDay: _focusedDay,
      selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
      calendarFormat: CalendarFormat.month,
      rowHeight: 58.0,
      daysOfWeekHeight: 24.0,
      headerStyle: const HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
        leftChevronIcon: Icon(Icons.chevron_left_rounded, color: Color(0xFF0F172A)),
        rightChevronIcon: Icon(Icons.chevron_right_rounded, color: Color(0xFF0F172A)),
        titleTextStyle: TextStyle(
          color: Color(0xFF0F172A),
          fontSize: 16,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.0,
        ),
        headerPadding: EdgeInsets.symmetric(vertical: 8),
      ),
      daysOfWeekStyle: const DaysOfWeekStyle(
        weekdayStyle: TextStyle(color: Color(0xFF484848), fontWeight: FontWeight.bold, fontSize: 12),
        weekendStyle: TextStyle(color: Color(0xFF767676), fontWeight: FontWeight.bold, fontSize: 12),
      ),
      calendarBuilders: CalendarBuilders(
        defaultBuilder: (context, day, focusedDay) =>
            _buildCalendarCell(day, isSelected: false, isToday: isSameDay(day, DateTime.now()), isOutside: false),
        todayBuilder: (context, day, focusedDay) =>
            _buildCalendarCell(day, isSelected: false, isToday: true, isOutside: false),
        selectedBuilder: (context, day, focusedDay) =>
            _buildCalendarCell(day, isSelected: true, isToday: isSameDay(day, DateTime.now()), isOutside: false),
        outsideBuilder: (context, day, focusedDay) =>
            _buildCalendarCell(day, isSelected: false, isToday: isSameDay(day, DateTime.now()), isOutside: true),
      ),
      onDaySelected: (selectedDay, focusedDay) {
        setState(() {
          _selectedDay = selectedDay;
          _focusedDay = focusedDay;
        });
      },
      onPageChanged: (focusedDay) {
        setState(() {
          _focusedDay = focusedDay;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CalendarEvent>>(
      stream: _bookingsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && _events.isEmpty) {
          return _buildLoadingScreen();
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  'Error connecting to database: ${snapshot.error}\n\nPlease check your internet connection or Firestore rules.',
                  style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        final list = snapshot.data ?? [];

        // Auto-seed if database is empty and repository is Firestore
        if (list.isEmpty && widget.repository is FirestoreBookingRepository && !_isSeeding) {
          _isSeeding = true;
          _seedFirestore();
        }

        // Parse list events into local normalized map
        final Map<DateTime, List<CalendarEvent>> loadedEvents = {};
        for (var event in list) {
          final normalizedDate = _normalizeDate(event.date);
          
          if (loadedEvents[normalizedDate] == null) {
            loadedEvents[normalizedDate] = [];
          }
          loadedEvents[normalizedDate]!.add(event);
        }

        _events = loadedEvents;
        final formattedSelectedDate = DateFormat('MMMM d, yyyy').format(_selectedDay);

        return Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth > 950;
              
              if (isDesktop) {
                return Row(
                  children: [
                    // Desktop Left Sidebar Navigation
                    _buildSidebar(),
                    // Main Content Split Pane
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // LEFT PANE: Stats, Calendar, Legend, Copy button
                            Expanded(
                              flex: 6,
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    _buildHeaderBar(),
                                    const SizedBox(height: 16),
                                    _buildStatsRow(),
                                    const SizedBox(height: 16),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(24),
                                          boxShadow: _buildSoftShadow(),
                                        ),
                                        padding: const EdgeInsets.all(16.0),
                                        child: _buildCalendarWidget(),
                                      ),
                                    ),
                                    _buildLegend(),
                                    const SizedBox(height: 8),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                      child: _buildCopyButton(),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 24),
                            // RIGHT PANE: Bookings card
                            Expanded(
                              flex: 4,
                              child: _buildDesktopBookingsPane(formattedSelectedDate),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              } else {
                // Mobile Portrait layout
                return Scaffold(
                  extendBodyBehindAppBar: false,
                  appBar: PreferredSize(
                    preferredSize: const Size.fromHeight(76),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF1E293B).withOpacity(0.06),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                padding: const EdgeInsets.all(9),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(13),
                                  boxShadow: _buildSoftShadow(),
                                ),
                                child: _buildLogo(size: 22),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'APERTUREFLOW',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.5,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Availability Dashboard',
                                      style: TextStyle(fontSize: 11, color: Colors.black45, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              _buildNotificationBell(size: 38, iconSize: 18),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  body: SafeArea(
                    child: CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: _buildStatsRow(),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: _buildSoftShadow(),
                              ),
                              padding: const EdgeInsets.all(16.0),
                              child: _buildCalendarWidget(),
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: _buildLegend(),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                            child: _buildCopyButton(),
                          ),
                        ),
                        const SliverToBoxAdapter(
                          child: SizedBox(height: 12),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 4.0),
                            child: Row(
                              children: [
                                const Icon(Icons.bookmarks_outlined, color: Colors.black38, size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  'BOOKINGS: $formattedSelectedDate',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.2,
                                    color: Color(0xFF484848),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        _buildSliverEventList(),
                        const SliverToBoxAdapter(
                          child: SizedBox(height: 80),
                        ),
                      ],
                    ),
                  ),
                  floatingActionButton: FloatingActionButton.extended(
                    onPressed: _openAddEventForm,
                    label: const Text(
                      'NEW BOOKING',
                      style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.0, fontSize: 13),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 20),
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                );
              }
            },
          ),
          floatingActionButton: MediaQuery.of(context).size.width > 950
              ? FloatingActionButton.extended(
                  onPressed: _openAddEventForm,
                  label: const Text(
                    'NEW BOOKING',
                    style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.0, fontSize: 13),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 20),
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                )
              : null,
        );
      },
    );
  }
}
