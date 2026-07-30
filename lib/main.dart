import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'home_page.dart';
import 'fence_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Skip all diagnostic logging work in release builds.
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }
  // Fire-and-forget: geofence engine init is only needed by the time an
  // alarm is saved, so don't block first-frame rendering on it.
  FenceManager.init().catchError((e) {
    debugPrint('Geofence init failed (unsupported platform?): $e');
  });
  runApp(const GeoAlarmApp());
}

// ─── Colour Palette (from uploaded swatch) ────────────────────────────────
class AppColors {
  static const crimson  = Color(0xFFA31545);
  static const red      = Color(0xFFE8453C);
  static const orange   = Color(0xFFF2763A);
  static const amber    = Color(0xFFF9B234);
  static const yellow   = Color(0xFFFFF0A0);
  static const lime     = Color(0xFFD4EE8A);
  static const mint     = Color(0xFFA8E6C3);
  static const teal     = Color(0xFF5EC8C0);
  static const sky      = Color(0xFF4AA8D8);
  static const blue     = Color(0xFF3A6FC4);
  static const indigo   = Color(0xFF6B5EA8);

  // Semantic roles
  static const primary      = teal;       // main CTA, active states
  static const primaryDark  = Color(0xFF3AADA6); // pressed teal
  static const accent       = orange;     // highlights, active alarm dot
  static const success      = mint;
  static const warning      = amber;
  static const danger       = red;
  static const background   = Color(0xFFF9FAFB);
  static const surface      = Colors.white;
  static const textPrimary  = Color(0xFF1A202C);
  static const textSecondary= Color(0xFF6B7280);
  static const textHint     = Color(0xFFB0B7C3);
  static const divider      = Color(0xFFEEF0F3);
}

// ─── Theme ───────────────────────────────────────────────────────────────────
class AppTheme {
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.sky,
      surface: AppColors.surface,
    ),
    fontFamily: 'SF Pro Display', // falls back to system sans
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: IconThemeData(color: AppColors.textPrimary),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.background,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 14),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: AppColors.primary,
      inactiveTrackColor: AppColors.mint.withOpacity(0.35),
      thumbColor: AppColors.primary,
      overlayColor: AppColors.primary.withOpacity(0.12),
      trackHeight: 4,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
      s.contains(WidgetState.selected) ? Colors.white : AppColors.textHint),
      trackColor: WidgetStateProperty.resolveWith((s) =>
      s.contains(WidgetState.selected) ? AppColors.primary : AppColors.divider),
    ),
    dividerColor: AppColors.divider,
  );

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: const Color(0xFF0F1419),
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.sky,
      surface: const Color(0xFF1A1F2E),
      brightness: Brightness.dark,
    ),
    fontFamily: 'SF Pro Display',
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1A1F2E),
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: Color(0xFFE8EAED),
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: IconThemeData(color: Color(0xFFE8EAED)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF252D3D),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF3A4556)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF3A4556)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      hintStyle: const TextStyle(color: Color(0xFF8A92A3), fontSize: 14),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: AppColors.primary,
      inactiveTrackColor: AppColors.mint.withOpacity(0.2),
      thumbColor: AppColors.primary,
      overlayColor: AppColors.primary.withOpacity(0.12),
      trackHeight: 4,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
      s.contains(WidgetState.selected) ? Colors.white : const Color(0xFF5A6370)),
      trackColor: WidgetStateProperty.resolveWith((s) =>
      s.contains(WidgetState.selected) ? AppColors.primary : const Color(0xFF3A4556)),
    ),
    dividerColor: const Color(0xFF3A4556),
  );
}

// ─── App Root ────────────────────────────────────────────────────────────────
class GeoAlarmApp extends StatefulWidget {
  const GeoAlarmApp({super.key});

  @override
  State<GeoAlarmApp> createState() => _GeoAlarmAppState();
}

class _GeoAlarmAppState extends State<GeoAlarmApp> {
  bool _isDarkMode = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GeoAlarm',
      theme: _isDarkMode ? AppTheme.dark : AppTheme.light,
      debugShowCheckedModeBanner: false,
      home: AlarmsListPage(
        isDarkMode: _isDarkMode,
        onThemeChanged: (isDark) {
          setState(() => _isDarkMode = isDark);
        },
      ),
    );
  }
}

// ─── Data Model ───────────────────────────────────────────────────────────────
class AlarmModel {
  String id;
  String name, route;
  double latitude, longitude;
  int radius, leadMinutes;
  List<String> alertTypes;
  Color color;
  IconData icon;
  bool isActive;
  String transportType;
  bool soundOn, vibrateOn, notifOn, repeatOn, snoozeBlock;
  String ringtoneName;
  String ringtoneUri;

  AlarmModel({
    required this.id,
    required this.name,
    required this.route,
    required this.latitude,
    required this.longitude,
    required this.radius,
    required this.leadMinutes,
    required this.alertTypes,
    required this.color,
    required this.icon,
    required this.isActive,
    required this.transportType,
    this.soundOn = true,
    this.vibrateOn = true,
    this.notifOn = true,
    this.repeatOn = false,
    this.snoozeBlock = true,
    this.ringtoneName = 'Default Alarm',
    this.ringtoneUri = '',
  });

  // Convert to JSON
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'route': route,
    'latitude': latitude,
    'longitude': longitude,
    'radius': radius,
    'leadMinutes': leadMinutes,
    'alertTypes': alertTypes,
    'colorValue': color.value,
    'iconCodePoint': icon.codePoint,
    'isActive': isActive,
    'transportType': transportType,
    'soundOn': soundOn,
    'vibrateOn': vibrateOn,
    'notifOn': notifOn,
    'repeatOn': repeatOn,
    'snoozeBlock': snoozeBlock,
    'ringtoneName': ringtoneName,
    'ringtoneUri': ringtoneUri,
  };

  // Create from JSON
  factory AlarmModel.fromJson(Map<String, dynamic> json) {
    return AlarmModel(
      id: json['id'] as String? ?? 'unknown',
      name: json['name'] as String? ?? '',
      route: json['route'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      radius: json['radius'] as int? ?? 250,
      leadMinutes: json['leadMinutes'] as int? ?? 0,
      alertTypes: List<String>.from(json['alertTypes'] as List? ?? []),
      color: Color(json['colorValue'] as int? ?? 0xFF5EC8C0),
      // Constant icon: dynamic IconData breaks icon tree-shaking in
      // release builds, and all alarms use the location icon anyway.
      icon: Icons.location_on_rounded,
      isActive: json['isActive'] as bool? ?? true,
      transportType: json['transportType'] as String? ?? 'Any',
      soundOn: json['soundOn'] as bool? ?? true,
      vibrateOn: json['vibrateOn'] as bool? ?? true,
      notifOn: json['notifOn'] as bool? ?? true,
      repeatOn: json['repeatOn'] as bool? ?? false,
      snoozeBlock: json['snoozeBlock'] as bool? ?? true,
      ringtoneName: json['ringtoneName'] as String? ?? 'Default Alarm',
      ringtoneUri: json['ringtoneUri'] as String? ?? '',
    );
  }
}

// ─── Alarm Storage Helper ──────────────────────────────────────────────────────
class AlarmStorage {
  static const String _key = 'saved_alarms';

  static Future<List<AlarmModel>> loadAlarms() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_key);
      
      if (jsonString == null) {
        debugPrint('No saved alarms found');
        return [];
      }

      debugPrint('Found saved alarms: ${jsonString.length} characters');
      final List<dynamic> jsonList = jsonDecode(jsonString);
      final alarms = jsonList.map((json) => AlarmModel.fromJson(json)).toList();
      debugPrint('✅ Loaded ${alarms.length} alarms from storage');
      return alarms;
    } catch (e) {
      debugPrint('❌ Error loading alarms: $e');
      return [];
    }
  }

  static Future<void> saveAlarm(AlarmModel alarm) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alarms = await loadAlarms();

      // Add or update alarm
      final index = alarms.indexWhere((a) => a.id == alarm.id);
      if (index >= 0) {
        alarms[index] = alarm;
      } else {
        alarms.add(alarm);
      }

      final jsonString = jsonEncode(alarms.map((a) => a.toJson()).toList());
      await prefs.setString(_key, jsonString);
      debugPrint('✅ Alarm saved. Total alarms: ${alarms.length}');
    } catch (e, stackTrace) {
      debugPrint('❌ Error saving alarm: $e\n$stackTrace');
      rethrow;
    }
  }

  static Future<void> deleteAlarm(String alarmId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alarms = await loadAlarms();
      alarms.removeWhere((a) => a.id == alarmId);
      
      final jsonString = jsonEncode(alarms.map((a) => a.toJson()).toList());
      await prefs.setString(_key, jsonString);
    } catch (e) {
      debugPrint('Error deleting alarm: $e');
    }
  }

  static Future<void> updateAlarmStatus(String alarmId, bool isActive) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alarms = await loadAlarms();
      
      final index = alarms.indexWhere((a) => a.id == alarmId);
      if (index >= 0) {
        alarms[index].isActive = isActive;
        final jsonString = jsonEncode(alarms.map((a) => a.toJson()).toList());
        await prefs.setString(_key, jsonString);
      }
    } catch (e) {
      debugPrint('Error updating alarm status: $e');
    }
  }
}
