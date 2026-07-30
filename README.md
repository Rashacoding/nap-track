# NapTrack

NapTrack is a location-based alarm app for travelers who don't want to miss their stop. Instead of a timer, you set a geofence around your destination — a bus stop, train station, or any point on the map — and NapTrack wakes you up as you approach it, so you can nap through the rest of the ride.

Built with Flutter, using native geofencing (not GPS polling in Dart) so alarms keep working in the background and even if the app is closed.

## Features

- **Geofenced alarms** — pick a destination on the map or search an address, set a radius, and get alerted on arrival.
- **Lead time** — get notified a few minutes *before* you arrive, not just on arrival. The fence radius is automatically widened based on your selected transport mode (bus, train, car) and its typical speed, so the early alert fires at roughly the right time regardless of how fast you're moving.
- **Custom alerts** — toggle sound, vibration, and notifications independently per alarm.
- **Custom ringtones** — pick a system ringtone or import your own audio file, with in-app preview before saving.
- **Active/inactive alarms** — keep saved alarms around and toggle them on or off without deleting them.
- **Light & dark themes** — switchable from the alarms list.
- **Works offline in the background** — geofence triggers and notifications run in a native background isolate, so alarms fire even if the app isn't in the foreground.

## Tech stack

- [Flutter](https://flutter.dev) / Dart
- [`native_geofence`](https://pub.dev/packages/native_geofence) for OS-level geofence registration and background triggers
- [`flutter_local_notifications`](https://pub.dev/packages/flutter_local_notifications) for full-screen arrival alerts
- [`flutter_map`](https://pub.dev/packages/flutter_map) + [`geocoding`](https://pub.dev/packages/geocoding) + [`geolocator`](https://pub.dev/packages/geolocator) for the destination map picker and address search
- [`just_audio`](https://pub.dev/packages/just_audio) + [`file_picker`](https://pub.dev/packages/file_picker) for custom ringtone import/preview
- [`shared_preferences`](https://pub.dev/packages/shared_preferences) for local alarm storage

## Getting started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart ^3.8.0)
- Android Studio / Xcode for platform builds
- A physical device is recommended for testing — location/geofencing behavior is limited on simulators/emulators

### Setup

```bash
git clone <repo-url>
cd nap-track
flutter pub get
flutter run
```

### Permissions

NapTrack requests the following at runtime:
- Location (when in use, and "always" for background geofencing)
- Notifications

Background ("always") location is requested but not strictly required — geofences still trigger while the app is in the foreground without it.

## Project structure

```
lib/
├── main.dart            # App entry point, theming, alarm data model & local storage
├── home_page.dart        # Alarms list screen
├── alarm_set_page.dart   # New alarm creation screen
├── map_picker_page.dart  # Interactive map for choosing a destination
└── fence_manager.dart    # Native geofence registration & background trigger handling
```

## License

No license specified yet.
