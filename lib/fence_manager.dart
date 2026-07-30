import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:native_geofence/native_geofence.dart';
import 'package:permission_handler/permission_handler.dart';

import 'main.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Geofence background callback
//
// Runs in a background isolate — it may fire while the app is closed, so it
// cannot touch any UI. It re-initializes the notification plugin and shows a
// full-screen alarm notification.
// ═══════════════════════════════════════════════════════════════════════════
@pragma('vm:entry-point')
Future<void> fenceTriggered(GeofenceCallbackParams params) async {
  if (params.event != GeofenceEvent.enter) return;

  final notifications = FlutterLocalNotificationsPlugin();
  await notifications.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ),
  );

  final alarms = await AlarmStorage.loadAlarms();

  for (final fence in params.geofences) {
    final alarm = alarms.where((a) => a.id == fence.id).firstOrNull;
    if (alarm != null && !alarm.isActive) continue;

    final name = alarm?.name ?? 'your stop';
    final soundOn = alarm?.soundOn ?? true;
    final vibrateOn = alarm?.vibrateOn ?? true;
    final ringtoneUri = alarm?.ringtoneUri ?? '';
    final hasCustomSound =
        ringtoneUri.isNotEmpty && ringtoneUri.startsWith('content://');

    await notifications.show(
      id: fence.id.hashCode,
      title: 'Wake up — $name!',
      body: alarm != null && alarm.leadMinutes > 0
          ? 'You are about ${alarm.leadMinutes} min from ${alarm.route}'
          : 'You have arrived near ${alarm?.route ?? 'your destination'}',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'nap_track_arrival',
          'Arrival alarms',
          channelDescription: 'Rings when you approach a saved destination',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.alarm,
          fullScreenIntent: true,
          playSound: soundOn,
          sound: soundOn && hasCustomSound
              ? UriAndroidNotificationSound(ringtoneUri)
              : null,
          audioAttributesUsage: AudioAttributesUsage.alarm,
          enableVibration: vibrateOn,
          autoCancel: false,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: soundOn,
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FenceManager — registers alarms as OS-native geofences
// ═══════════════════════════════════════════════════════════════════════════
class FenceManager {
  FenceManager._();

  /// Average speeds (km/h) used to widen the fence so the alert fires
  /// roughly [AlarmModel.leadMinutes] before arrival.
  static const _speedsKmh = <String, double>{
    'Bus': 30,
    'Train': 60,
    'Car': 45,
    'Any': 40,
  };

  static Future<void> init() async {
    await NativeGeofenceManager.instance.initialize();
  }

  /// Requests the permissions geofencing needs. Returns true if usable.
  ///
  /// Background ("always") location is requested but not required: without it
  /// the fence still triggers while the app is foregrounded.
  static Future<bool> ensurePermissions() async {
    final whenInUse = await Permission.locationWhenInUse.request();
    if (!whenInUse.isGranted) return false;
    await Permission.locationAlways.request();
    await Permission.notification.request();
    return true;
  }

  /// The fence radius in meters, widened by lead time × transport speed.
  static double effectiveRadiusMeters(AlarmModel alarm) {
    final speedKmh = _speedsKmh[alarm.transportType] ?? 40;
    final leadMeters = speedKmh * 1000 / 60 * alarm.leadMinutes;
    return alarm.radius + leadMeters;
  }

  static Future<void> register(AlarmModel alarm) async {
    final radius = effectiveRadiusMeters(alarm);
    // Larger fences tolerate slower checks: crossing a multi-km fence takes
    // minutes anyway, and higher responsiveness saves significant battery.
    final responsiveness = radius >= 2000
        ? const Duration(minutes: 2)
        : radius >= 500
            ? const Duration(minutes: 1)
            : const Duration(seconds: 30);
    final fence = Geofence(
      id: alarm.id,
      location: Location(latitude: alarm.latitude, longitude: alarm.longitude),
      radiusMeters: radius,
      triggers: const {GeofenceEvent.enter},
      iosSettings: const IosGeofenceSettings(initialTrigger: true),
      androidSettings: AndroidGeofenceSettings(
        initialTriggers: const {GeofenceEvent.enter},
        notificationResponsiveness: responsiveness,
      ),
    );
    await NativeGeofenceManager.instance.createGeofence(fence, fenceTriggered);
  }

  static Future<void> unregister(String alarmId) async {
    await NativeGeofenceManager.instance.removeGeofenceById(alarmId);
  }

  /// Registers or removes the fence to match the alarm's active flag.
  static Future<void> sync(AlarmModel alarm) async {
    if (alarm.isActive && alarm.latitude != 0 && alarm.longitude != 0) {
      await register(alarm);
    } else {
      await unregister(alarm.id);
    }
  }
}
