import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Reminders are scheduled in the device's zone; this one if it can't be read.
const String _fallbackTimeZone = 'Asia/Tashkent';

/// Schedules local "time to review" reminders on Android, iOS, macOS and
/// Windows — a safe no-op on web and Linux, which can't schedule them.
class NotificationService {
  NotificationService([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  static const int _dailyReminderId = 1001;
  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'review_reminders',
      'Review reminders',
      channelDescription: 'Daily nudges to review your knowledge',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
    windows: WindowsNotificationDetails(),
  );

  /// Whether this platform can schedule reminders.
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform != TargetPlatform.linux;

  /// Initializes the plugin and the timezone database. Call once at startup.
  Future<void> init() async {
    if (!supported) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation(await FlutterTimezone.getLocalTimezone()));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation(_fallbackTimeZone));
    }
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: darwin,
      macOS: darwin,
      windows: WindowsInitializationSettings(
        appName: 'Bilig',
        appUserModelId: 'Bilig.Bilig.Notes',
        guid: '6f1c3b0e-5d2a-4f7e-9b1c-8a4e2d7f3c51',
      ),
    );
    try {
      await _plugin.initialize(settings);
      _ready = true;
    } catch (_) {
      // Reminders are a nicety; the app works without them.
    }
  }

  /// Requests notification permission (Android 13+, iOS, macOS). Returns
  /// true if granted (or if the platform doesn't gate it).
  Future<bool> requestPermission() async {
    if (kIsWeb || !_ready) return false;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? true;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, badge: true, sound: true) ??
          true;
    }
    final macos = _plugin.resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin>();
    if (macos != null) {
      return await macos.requestPermissions(
              alert: true, badge: true, sound: true) ??
          true;
    }
    return true; // Windows doesn't ask.
  }

  /// (Re)schedules a daily reminder at [hour]:[minute]. Prefers exact alarms so
  /// it fires on time; if the OS denies exact-alarm permission it falls back to
  /// inexact scheduling (which Android may delay to save battery).
  Future<void> scheduleDailyReminder(int hour, int minute,
      {required String body}) async {
    if (kIsWeb || !_ready) return;
    await cancelDailyReminder();
    Future<void> schedule(AndroidScheduleMode mode) => _plugin.zonedSchedule(
          _dailyReminderId,
          'Bilig',
          body,
          _nextInstanceOf(hour, minute),
          _details,
          androidScheduleMode: mode,
          matchDateTimeComponents: DateTimeComponents.time,
        );
    try {
      await schedule(AndroidScheduleMode.exactAllowWhileIdle);
    } catch (_) {
      await schedule(AndroidScheduleMode.inexactAllowWhileIdle);
    }
  }

  Future<void> cancelDailyReminder() async {
    if (kIsWeb || !_ready) return;
    await _plugin.cancel(_dailyReminderId);
    for (var i = 0; i < reminderDays; i++) {
      await _plugin.cancel(_dailyReminderId + 1 + i);
    }
  }

  /// Days of reminders scheduled ahead (rescheduled whenever notes change).
  static const int reminderDays = 7;

  /// Schedules one reminder per entry of [plan] (when → text), at most
  /// [reminderDays] of them; the rest of the week stays quiet.
  Future<void> scheduleReminders(Map<DateTime, String> plan) async {
    if (kIsWeb || !_ready) return;
    await cancelDailyReminder();
    var i = 0;
    for (final e in plan.entries.take(reminderDays)) {
      final id = _dailyReminderId + 1 + i++;
      final at = tz.TZDateTime.from(e.key, tz.local);
      Future<void> schedule(AndroidScheduleMode mode) => _plugin.zonedSchedule(
            id, 'Bilig', e.value, at, _details, androidScheduleMode: mode);
      try {
        await schedule(AndroidScheduleMode.exactAllowWhileIdle);
      } catch (_) {
        await schedule(AndroidScheduleMode.inexactAllowWhileIdle);
      }
    }
  }

  tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
