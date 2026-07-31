import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

// ═══════════════════════════════════════════════════════════════════════════
// Central alarm-notification helper.
//
// Shared by the geofence background isolate (fence_manager.dart), the main
// isolate (main.dart) and the ringing screen (alarm_ring_page.dart). Owns the
// Android notification channel, the Stop/Snooze action wiring, and snooze
// rescheduling. A single top-level module works across isolates because each
// isolate gets its own copy of these top-level members.
// ═══════════════════════════════════════════════════════════════════════════

const String alarmChannelId = 'nap_track_alarm_v2';
const String alarmCategoryId = 'nap_track_alarm_category';
const String actionStop = 'stop';
const String actionSnooze = 'snooze';
const Duration snoozeDuration = Duration(minutes: 5);

final FlutterLocalNotificationsPlugin alarmPlugin =
    FlutterLocalNotificationsPlugin();

/// Broadcasts every notification response received while the app is alive,
/// so the UI (main.dart) can push the ringing screen for a plain tap.
final StreamController<NotificationResponse> alarmResponses =
    StreamController<NotificationResponse>.broadcast();

bool _tzReady = false;

void _ensureTimeZones() {
  if (_tzReady) return;
  tzdata.initializeTimeZones();
  _tzReady = true;
}

/// JSON payload embedded in every alarm notification, carrying everything
/// needed to re-show or reschedule it without re-reading storage.
class AlarmPayload {
  final int id;
  final String title;
  final String body;
  final String ringtoneUri;
  final bool soundOn;
  final bool vibrateOn;

  const AlarmPayload({
    required this.id,
    required this.title,
    required this.body,
    required this.ringtoneUri,
    required this.soundOn,
    required this.vibrateOn,
  });

  String encode() => jsonEncode({
        'id': id,
        'title': title,
        'body': body,
        'ringtoneUri': ringtoneUri,
        'soundOn': soundOn,
        'vibrateOn': vibrateOn,
      });

  static AlarmPayload? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return AlarmPayload(
        id: map['id'] as int,
        title: map['title'] as String? ?? 'Wake up!',
        body: map['body'] as String? ?? '',
        ringtoneUri: map['ringtoneUri'] as String? ?? '',
        soundOn: map['soundOn'] as bool? ?? true,
        vibrateOn: map['vibrateOn'] as bool? ?? true,
      );
    } catch (e) {
      debugPrint('Failed to decode alarm payload: $e');
      return null;
    }
  }
}

/// Registers the plugin, the Android notification channel and the
/// Stop/Snooze action wiring. Call once per isolate before showing/handling
/// any alarm notification.
Future<void> initAlarmNotifications() async {
  final iosCategory = DarwinNotificationCategory(
    alarmCategoryId,
    actions: [
      DarwinNotificationAction.plain(actionSnooze, 'Snooze'),
      DarwinNotificationAction.plain(
        actionStop,
        'Stop',
        options: {DarwinNotificationActionOption.destructive},
      ),
    ],
    options: {DarwinNotificationCategoryOption.allowAnnouncement},
  );

  await alarmPlugin.initialize(
    settings: InitializationSettings(
      android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        notificationCategories: [iosCategory],
      ),
    ),
    onDidReceiveNotificationResponse: (response) {
      alarmResponses.add(response);
      unawaited(_handleResponse(response));
    },
    onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
  );

  final androidPlugin = alarmPlugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  if (androidPlugin != null) {
    // Created once with fixed sound/vibration: Android locks a channel's
    // sound/vibration settings in at first creation and silently ignores
    // any different values passed on later notifications, so per-alarm
    // sound/vibrate toggles can never reach the OS channel after the fact.
    // Those toggles instead control the in-app ringing loop (AlarmRingPage);
    // this channel just needs sane, unchanging defaults.
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        alarmChannelId,
        'Arrival alarms',
        description: 'Rings when you approach a saved destination',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('alarm_default'),
        enableVibration: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
      ),
    );
  }
}

/// Background-isolate entry point for notification action taps (Stop/Snooze)
/// when the app is fully terminated. Must stay a top-level/static function.
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  _handleResponse(response);
}

Future<void> _handleResponse(NotificationResponse response) async {
  final payload = AlarmPayload.decode(response.payload);
  if (payload == null) return;

  switch (response.actionId) {
    case actionStop:
      await cancelAlarm(payload.id);
      break;
    case actionSnooze:
      await cancelAlarm(payload.id);
      await scheduleSnooze(payload);
      break;
    default:
      // Plain tap: handled via [alarmResponses] in the foreground, or via
      // getNotificationAppLaunchDetails() on cold start. Nothing to do here.
      break;
  }
}

NotificationDetails _detailsFor(AlarmPayload payload) {
  return NotificationDetails(
    android: AndroidNotificationDetails(
      alarmChannelId,
      'Arrival alarms',
      channelDescription: 'Rings when you approach a saved destination',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      autoCancel: false,
      ongoing: true,
      actions: const [
        AndroidNotificationAction(actionSnooze, 'Snooze'),
        AndroidNotificationAction(
          actionStop,
          'Stop',
          cancelNotification: true,
        ),
      ],
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentSound: payload.soundOn,
      interruptionLevel: InterruptionLevel.timeSensitive,
      categoryIdentifier: alarmCategoryId,
    ),
  );
}

/// Shows (or re-shows, for a snooze) the full-screen alarm notification.
Future<void> showAlarm(AlarmPayload payload) async {
  await alarmPlugin.show(
    id: payload.id,
    title: payload.title,
    body: payload.body,
    notificationDetails: _detailsFor(payload),
    payload: payload.encode(),
  );
}

Future<void> cancelAlarm(int id) async {
  await alarmPlugin.cancel(id: id);
}

/// Re-shows the alarm [snoozeDuration] from now, falling back to inexact
/// timing if exact alarm scheduling isn't permitted (Android 12+).
Future<void> scheduleSnooze(AlarmPayload payload) async {
  _ensureTimeZones();
  final when = tz.TZDateTime.now(tz.local).add(snoozeDuration);
  try {
    await alarmPlugin.zonedSchedule(
      id: payload.id,
      title: payload.title,
      body: payload.body,
      scheduledDate: when,
      notificationDetails: _detailsFor(payload),
      payload: payload.encode(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  } catch (e) {
    debugPrint('Exact snooze scheduling failed, falling back: $e');
    await alarmPlugin.zonedSchedule(
      id: payload.id,
      title: payload.title,
      body: payload.body,
      scheduledDate: when,
      notificationDetails: _detailsFor(payload),
      payload: payload.encode(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }
}
