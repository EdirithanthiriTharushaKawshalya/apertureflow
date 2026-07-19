import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Wraps [FlutterLocalNotificationsPlugin] to schedule and cancel booking
/// reminder notifications, keyed off the booking's Firestore document id.
class NotificationService {
  NotificationService._internal();
  static final NotificationService instance = NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const String _channelId = 'booking_reminders';
  static const String _channelName = 'Booking Reminders';
  static const String _channelDescription = 'Reminders for upcoming shoots and equipment rentals.';

  /// Maps a booking's Firestore document id to a stable 32-bit notification id.
  int _notificationIdFor(String bookingId) => bookingId.hashCode & 0x7fffffff;

  Future<void> init() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();
    try {
      final localTimeZone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTimeZone.identifier));
    } catch (e) {
      debugPrint('Falling back to UTC timezone: $e');
    }

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      settings: const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );

    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _initialized = true;
  }

  /// Requests notification permission (Android 13+ / iOS) and, on Android,
  /// the exact-alarm permission needed for precisely-timed reminders.
  Future<void> requestPermissions() async {
    if (Platform.isIOS || Platform.isMacOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } else if (Platform.isAndroid) {
      final androidPlugin =
          _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
      await androidPlugin?.requestExactAlarmsPermission();
    }
  }

  /// Schedules (or reschedules) a reminder for [bookingId] at [reminderTime],
  /// with a title/body describing the booking. No-ops if the time has already passed.
  Future<void> scheduleReminder({
    required String bookingId,
    required DateTime reminderTime,
    required String eventType,
    required String eventDate,
    required String notes,
  }) async {
    await cancelReminder(bookingId);

    if (reminderTime.isBefore(DateTime.now())) return;

    final scheduledDate = tz.TZDateTime.from(reminderTime, tz.local);

    await _plugin.zonedSchedule(
      id: _notificationIdFor(bookingId),
      title: '$eventType Reminder',
      body: '$eventDate — $notes',
      scheduledDate: scheduledDate,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  Future<void> cancelReminder(String bookingId) async {
    await _plugin.cancel(id: _notificationIdFor(bookingId));
  }

  /// Formats a friendly default label for a reminder moment, e.g. "Jul 19, 9:00 AM".
  static String formatReminder(DateTime dateTime) {
    return DateFormat('MMM d, h:mm a').format(dateTime);
  }
}
