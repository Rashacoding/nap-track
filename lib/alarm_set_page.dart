import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart';
import 'package:flutter_system_ringtones/flutter_system_ringtones.dart';
import 'package:flutter_ringtone_manager/flutter_ringtone_manager.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:just_audio/just_audio.dart';
import 'package:latlong2/latlong.dart';
import 'fence_manager.dart';
import 'map_picker_page.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PAGE 2 — New Alarm Setup
// ═══════════════════════════════════════════════════════════════════════════
class NewAlarmPage extends StatefulWidget {
  const NewAlarmPage({super.key});

  @override
  State<NewAlarmPage> createState() => _NewAlarmPageState();
}

class _NewAlarmPageState extends State<NewAlarmPage> {
  final _ringtoneManager = FlutterRingtoneManager();
  final _previewPlayer = AudioPlayer();
  double _radius = 250;
  int _selectedTransport = 0;
  int _selectedLead = 1;
  bool _soundOn = true;
  bool _vibrateOn = true;
  bool _notifOn = true;
  bool _repeatOn = false;
  bool _snoozeBlock = true;

  late TextEditingController _nameController;
  late TextEditingController _destinationController;

  // Destination coordinates, filled by the GPS button or by geocoding the
  // typed address on save. Cleared whenever the text changes so stale
  // coordinates are never saved.
  double? _destLat;
  double? _destLng;
  bool _locating = false;

  List<Ringtone> _ringtones = [];
  String _selectedRingtoneName = 'Default Alarm';
  String _selectedRingtoneUri = '';

  static const List<Ringtone> _mockRingtones = [
    Ringtone(id: 'mock_default', title: 'Default Alarm', uri: 'default'),
    Ringtone(id: 'mock_cosmic', title: 'Cosmic Pulse', uri: 'cosmic'),
    Ringtone(id: 'mock_sunrise', title: 'Sunrise Melody', uri: 'sunrise'),
    Ringtone(id: 'mock_dew', title: 'Morning Dew', uri: 'dew'),
    Ringtone(id: 'mock_siren', title: 'Cyberpunk Siren', uri: 'siren'),
    Ringtone(id: 'mock_bell', title: 'Classic Bell', uri: 'bell'),
  ];

  final _transports = [
    {'label': 'Bus',   'icon': Icons.directions_bus_rounded},
    {'label': 'Train', 'icon': Icons.train_rounded},
    {'label': 'Car',   'icon': Icons.directions_car_rounded},
    {'label': 'Any',   'icon': Icons.circle_outlined},
  ];

  final _leadTimes = ['On arrival', '2 min', '5 min', '10 min'];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _destinationController = TextEditingController();
    _destinationController.addListener(() {
      _destLat = null;
      _destLng = null;
    });
    _loadRingtones();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _destinationController.dispose();
    _ringtoneManager.stop();
    _previewPlayer.dispose();
    super.dispose();
  }

  static const String _customRingtonesKey = 'custom_ringtones';

  Future<List<Ringtone>> _loadCustomRingtones() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_customRingtonesKey);
      if (raw == null) return [];
      final list = jsonDecode(raw) as List;
      return [
        for (final e in list)
          // Skip tones whose backing file was deleted.
          if (File(e['uri'] as String).existsSync())
            Ringtone(
              id: e['id'] as String,
              title: e['title'] as String,
              uri: e['uri'] as String,
            ),
      ];
    } catch (e) {
      debugPrint('Error loading custom ringtones: $e');
      return [];
    }
  }

  /// Opens the phone's native audio picker and adds the chosen file as a
  /// ringtone. The file is copied into app storage so it survives cache
  /// cleanup, and the entry is persisted for future sessions.
  Future<void> _addCustomRingtone(StateSetter setModalState) async {
    try {
      final result = await FilePicker.pickFiles(type: FileType.audio);
      final picked = result?.files.firstOrNull;
      final sourcePath = picked?.path;
      if (picked == null || sourcePath == null) return;

      final docs = await getApplicationDocumentsDirectory();
      final tonesDir = Directory('${docs.path}/ringtones');
      if (!tonesDir.existsSync()) tonesDir.createSync(recursive: true);
      final destPath = '${tonesDir.path}/${picked.name}';
      await File(sourcePath).copy(destPath);

      final title = picked.name.replaceAll(RegExp(r'\.[^.]+$'), '');
      final tone = Ringtone(
        id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
        title: title,
        uri: destPath,
      );

      final existing = await _loadCustomRingtones();
      final all = [...existing, tone];
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _customRingtonesKey,
        jsonEncode([
          for (final t in all) {'id': t.id, 'title': t.title, 'uri': t.uri}
        ]),
      );

      if (mounted) {
        setState(() {
          _ringtones = [tone, ..._ringtones];
          _selectedRingtoneName = tone.title;
          _selectedRingtoneUri = tone.uri;
        });
        setModalState(() {});
      }
    } catch (e) {
      debugPrint('Error adding custom ringtone: $e');
      _showMessage('Could not add that audio file: $e');
    }
  }

  Future<void> _loadRingtones() async {
    try {
      // User-added tones first, then device alarm sounds (this is an alarm
      // app), then ringtones — deduplicated by URI.
      final custom = await _loadCustomRingtones();
      final alarmSounds = await FlutterSystemRingtones.getAlarmSounds();
      final ringtoneSounds = await FlutterSystemRingtones.getRingtoneSounds();
      final seenUris = <String>{};
      final combined = [...alarmSounds, ...ringtoneSounds]
          .where((r) => seenUris.add(r.uri))
          .toList();
      if (mounted) {
        setState(() {
          _ringtones = [
            ...custom,
            ...combined.isEmpty ? _mockRingtones : combined,
          ];
        });
      }
    } catch (e) {
      debugPrint('Error loading ringtones: $e');
      if (mounted) {
        setState(() {
          _ringtones = _mockRingtones;
        });
      }
    }
  }

  void _showMessage(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  /// Fills the destination field with the device's current position.
  Future<void> _useCurrentLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _showMessage('Please turn on location services');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showMessage('Location permission is needed to use your position');
        return;
      }

      // High (not best) accuracy with a time cap: cheaper on battery and
      // never hangs the UI waiting for a perfect fix.
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      String label =
          '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
      try {
        final placemarks =
            await geo.placemarkFromCoordinates(pos.latitude, pos.longitude);
        final p = placemarks.firstOrNull;
        if (p != null) {
          label = [p.name, p.locality]
              .where((s) => s != null && s.isNotEmpty)
              .join(', ');
        }
      } catch (_) {
        // Reverse geocoding is best-effort; keep the raw coordinates label.
      }

      _destinationController.text = label;
      // Set after updating the text: the listener clears coordinates on edit.
      _destLat = pos.latitude;
      _destLng = pos.longitude;
    } catch (e) {
      _showMessage('Could not get current location: $e');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// Opens the full-screen map picker and applies the chosen point.
  Future<void> _openMapPicker() async {
    final result = await Navigator.push<MapPickResult>(
      context,
      MaterialPageRoute(
        builder: (_) => MapPickerPage(
          initialLat: _destLat,
          initialLng: _destLng,
          radiusMeters: _radius,
        ),
      ),
    );
    if (result != null) {
      setState(() {
        // Set the text first: its listener clears the coordinates.
        _destinationController.text = result.label;
        _destLat = result.latitude;
        _destLng = result.longitude;
      });
    }
  }

  /// Resolves the typed address to coordinates. Returns false on failure.
  Future<bool> _resolveDestination() async {
    if (_destLat != null && _destLng != null) return true;
    try {
      final results =
          await geo.locationFromAddress(_destinationController.text.trim());
      final loc = results.firstOrNull;
      if (loc == null) return false;
      _destLat = loc.latitude;
      _destLng = loc.longitude;
      return true;
    } catch (e) {
      debugPrint('Geocoding failed: $e');
      return false;
    }
  }

  Future<void> _saveAlarm() async {
    if (_nameController.text.isEmpty || _destinationController.text.isEmpty) {
      debugPrint('❌ Validation failed: empty name or destination');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all required fields')),
      );
      return;
    }

    try {
      debugPrint('💾 Starting to save alarm...');

      if (!await _resolveDestination()) {
        _showMessage(
            'Could not find that destination — try a more specific address or use the GPS button');
        return;
      }

      final transportLabel = _transports[_selectedTransport]['label'] as String;
      final leadTime = int.tryParse(_leadTimes[_selectedLead].split(' ')[0]) ?? 0;

      final alarm = AlarmModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: _nameController.text,
        route: _destinationController.text,
        latitude: _destLat!,
        longitude: _destLng!,
        radius: _radius.toInt(),
        leadMinutes: leadTime,
        alertTypes: [
          if (_soundOn) 'Sound',
          if (_vibrateOn) 'Vibrate',
        ],
        color: AppColors.teal,
        icon: Icons.location_on_rounded,
        isActive: true,
        transportType: transportLabel,
        soundOn: _soundOn,
        vibrateOn: _vibrateOn,
        notifOn: _notifOn,
        repeatOn: _repeatOn,
        snoozeBlock: _snoozeBlock,
        ringtoneName: _selectedRingtoneName,
        ringtoneUri: _selectedRingtoneUri,
      );

      debugPrint('📝 Alarm model created: ${alarm.name} at ${alarm.route}');
      await AlarmStorage.saveAlarm(alarm);
      debugPrint('✅ AlarmStorage.saveAlarm completed');

      // Register the OS geofence for this alarm.
      try {
        final permitted = await FenceManager.ensurePermissions();
        if (permitted) {
          await FenceManager.register(alarm);
          debugPrint('✅ Geofence registered for ${alarm.name}');
        } else {
          _showMessage(
              'Alarm saved, but location permission is needed for it to trigger');
        }
      } catch (e) {
        debugPrint('❌ Geofence registration failed: $e');
        _showMessage('Alarm saved, but fence setup failed: $e');
      }

      if (mounted) {
        debugPrint('📱 Showing success snackbar');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Alarm saved!'),
            duration: Duration(seconds: 1),
          ),
        );
        debugPrint('🔙 Popping navigation');
        Navigator.pop(context);
      } else {
        debugPrint('⚠️ Widget not mounted, not popping');
      }
    } catch (e) {
      debugPrint('❌ Exception in _saveAlarm: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving alarm: $e')),
        );
      }
    }
  }

  void _showRingtonePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final textPrimary = isDark ? const Color(0xFFE8EAED) : AppColors.textPrimary;
            final textSecondary = isDark ? const Color(0xFF8A92A3) : AppColors.textSecondary;
            
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF3A4556) : AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Choose ringtone',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Divider(height: 1, color: isDark ? const Color(0xFF3A4556) : AppColors.divider),
                  // Add a tone from the phone via the native audio picker.
                  ListTile(
                    leading: Container(
                      width: 34, height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.teal.withOpacity(isDark ? 0.15 : 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.add_rounded,
                          color: AppColors.teal, size: 20),
                    ),
                    title: const Text(
                      'Add from phone',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.teal,
                      ),
                    ),
                    subtitle: Text(
                      'Pick any audio file on this device',
                      style: TextStyle(fontSize: 11, color: textSecondary),
                    ),
                    onTap: () => _addCustomRingtone(setModalState),
                  ),
                  Divider(height: 1, color: isDark ? const Color(0xFF3A4556) : AppColors.divider),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _ringtones.length,
                      itemBuilder: (context, index) {
                        final r = _ringtones[index];
                        final isSelected = r.title == _selectedRingtoneName;
                        final isMock = r.id.startsWith('mock_');
                        
                        return ListTile(
                          title: Text(
                            r.title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                              color: isSelected ? AppColors.teal : textPrimary,
                            ),
                          ),
                          leading: Icon(
                            isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                            color: isSelected ? AppColors.teal : textSecondary,
                            size: 20,
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.play_arrow_rounded, size: 22),
                            color: isSelected ? AppColors.teal : textSecondary,
                            onPressed: () async {
                              try {
                                await _ringtoneManager.stop();
                                await _previewPlayer.stop();
                                if (r.id.startsWith('custom_')) {
                                  // User-added audio file.
                                  await _previewPlayer.setAudioSource(
                                      AudioSource.uri(Uri.file(r.uri)));
                                  _previewPlayer.play();
                                } else if (!isMock &&
                                    r.uri.startsWith('content://')) {
                                  // Play the actual selected system sound.
                                  await _previewPlayer.setAudioSource(
                                      AudioSource.uri(Uri.parse(r.uri)));
                                  _previewPlayer.play();
                                } else {
                                  await _ringtoneManager.playAlarm();
                                }
                              } catch (e) {
                                debugPrint('Ringtone preview not supported on this platform: $e');
                              }
                            },
                          ),
                          onTap: () {
                            setState(() {
                              _selectedRingtoneName = r.title;
                              _selectedRingtoneUri = r.uri;
                            });
                            setModalState(() {});
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).then((value) {
      _ringtoneManager.stop();
      _previewPlayer.stop();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Theme-aware colors
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF252D3D) : AppColors.background;
    final dividerColor = isDark ? const Color(0xFF3A4556) : AppColors.divider;
    final textPrimary = isDark ? const Color(0xFFE8EAED) : AppColors.textPrimary;
    final textSecondary = isDark ? const Color(0xFF8A92A3) : AppColors.textSecondary;
    final textHint = isDark ? const Color(0xFF5A6370) : AppColors.textHint;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('New alarm'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: dividerColor),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [

          // ── Alarm Name ──────────────────────────────────────────────────
          _FormSection(
            label: 'Alarm name',
            icon: Icons.label_outline_rounded,
            child: TextField(
              controller: _nameController,
              decoration: const InputDecoration(hintText: 'e.g. Office stop, Airport…'),
            ),
          ),

          // ── Destination ─────────────────────────────────────────────────
          _FormSection(
            label: 'Destination',
            icon: Icons.location_on_outlined,
            child: Column(
              children: [
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _destinationController,
                      decoration: const InputDecoration(hintText: 'Search location or address…'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // GPS button
                  InkWell(
                    onTap: _useCurrentLocation,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 46, height: 46,
                      decoration: BoxDecoration(
                        color: AppColors.teal.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.teal.withOpacity(0.3)),
                      ),
                      child: _locating
                          ? const Padding(
                              padding: EdgeInsets.all(13),
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.teal),
                            )
                          : const Icon(Icons.my_location_rounded,
                              color: AppColors.teal, size: 20),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                // Map preview — tap to open the full-screen picker
                GestureDetector(
                  onTap: _openMapPicker,
                  // opaque: the live-map preview is wrapped in IgnorePointer,
                  // so without this taps on it would not reach this detector.
                  behavior: HitTestBehavior.opaque,
                  child: RepaintBoundary(
                    child: _MapPreview(
                      radius: _radius,
                      lat: _destLat,
                      lng: _destLng,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Fence Radius ────────────────────────────────────────────────
          _FormSection(
            label: 'Fence radius',
            icon: Icons.radar_rounded,
            // StatefulBuilder: drag ticks rebuild only this section; the rest
            // of the page (map preview) syncs once on release.
            child: StatefulBuilder(
              builder: (context, setSection) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                          _radius >= 1000
                              ? (_radius / 1000).toStringAsFixed(
                                  _radius % 1000 == 0 ? 0 : 1)
                              : '${_radius.round()}',
                          style: TextStyle(
                              fontSize: 28, fontWeight: FontWeight.w700,
                              color: textPrimary)),
                      const SizedBox(width: 4),
                      Text(_radius >= 1000 ? 'km' : 'metres',
                          style: TextStyle(fontSize: 13, color: textSecondary)),
                    ],
                  ),
                  Slider(
                    value: _radius,
                    min: 50, max: 10000, divisions: 199,
                    onChanged: (v) => setSection(() => _radius = v),
                    onChangeEnd: (_) => setState(() {}),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('50 m', style: TextStyle(fontSize: 11, color: textHint)),
                      Text('5 km', style: TextStyle(fontSize: 11, color: textHint)),
                      Text('10 km', style: TextStyle(fontSize: 11, color: textHint)),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── Transport Type ───────────────────────────────────────────────
          _FormSection(
            label: 'Transport type',
            icon: Icons.directions_bus_outlined,
            child: Row(
              children: List.generate(_transports.length, (i) {
                final sel = i == _selectedTransport;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedTransport = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: EdgeInsets.only(right: i < 3 ? 6 : 0),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: sel
                            ? AppColors.teal.withOpacity(isDark ? 0.2 : 0.12)
                            : backgroundColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: sel ? AppColors.teal : dividerColor,
                          width: sel ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(_transports[i]['icon'] as IconData,
                              size: 22,
                              color: sel ? AppColors.teal : textSecondary),
                          const SizedBox(height: 4),
                          Text(_transports[i]['label'] as String,
                              style: TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w500,
                                  color: sel ? AppColors.teal : textSecondary)),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),

          // ── Lead Time ────────────────────────────────────────────────────
          _FormSection(
            label: 'Alert lead time',
            icon: Icons.timer_outlined,
            child: Wrap(
              spacing: 8, runSpacing: 8,
              children: List.generate(_leadTimes.length, (i) {
                final sel = i == _selectedLead;
                return GestureDetector(
                  onTap: () => setState(() => _selectedLead = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel ? AppColors.sky.withOpacity(isDark ? 0.2 : 0.12) : backgroundColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: sel ? AppColors.sky : dividerColor,
                        width: sel ? 1.5 : 1,
                      ),
                    ),
                    child: Text(_leadTimes[i],
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500,
                            color: sel ? AppColors.sky : textSecondary)),
                  ),
                );
              }),
            ),
          ),

          // ── Alert Ringtone ──────────────────────────────────────────────
          _FormSection(
            label: 'Alert ringtone',
            icon: Icons.music_note_outlined,
            child: InkWell(
              onTap: _showRingtonePicker,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.audiotrack_rounded, color: AppColors.teal, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedRingtoneName,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Tap to change ringtone',
                            style: TextStyle(fontSize: 11, color: textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios_rounded, size: 14, color: textSecondary),
                  ],
                ),
              ),
            ),
          ),

          // ── Alert Type ───────────────────────────────────────────────────
          _FormSection(
            label: 'Alert type',
            icon: Icons.notifications_outlined,
            child: Column(children: [
              _AlertRow(
                icon: Icons.volume_up_rounded,
                iconColor: AppColors.orange,
                title: 'Sound alarm',
                subtitle: 'Plays alarm tone',
                value: _soundOn,
                onChanged: (v) => setState(() => _soundOn = v),
              ),
              _AlertRow(
                icon: Icons.vibration_rounded,
                iconColor: AppColors.indigo,
                title: 'Vibration',
                subtitle: 'Strong pulse pattern',
                value: _vibrateOn,
                onChanged: (v) => setState(() => _vibrateOn = v),
              ),
              _AlertRow(
                icon: Icons.phone_android_rounded,
                iconColor: AppColors.sky,
                title: 'Notification',
                subtitle: 'Banner + lock screen',
                value: _notifOn,
                onChanged: (v) => setState(() => _notifOn = v),
              ),
              _AlertRow(
                icon: Icons.repeat_rounded,
                iconColor: AppColors.amber,
                title: 'Repeat alert',
                subtitle: 'Every 30s until dismissed',
                value: _repeatOn,
                onChanged: (v) => setState(() => _repeatOn = v),
                showDivider: false,
              ),
            ]),
          ),

          // ── Safety ───────────────────────────────────────────────────────
          _FormSection(
            label: 'Safety options',
            icon: Icons.shield_outlined,
            child: _AlertRow(
              icon: Icons.lock_outline_rounded,
              iconColor: AppColors.crimson,
              title: 'Block snooze near stop',
              subtitle: 'Cannot snooze inside fence zone',
              value: _snoozeBlock,
              onChanged: (v) => setState(() => _snoozeBlock = v),
              showDivider: false,
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),

      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saveAlarm,
              icon: const Icon(Icons.check_rounded, size: 20),
              label: const Text('Save alarm'),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Form Section Wrapper ─────────────────────────────────────────────────────
class _FormSection extends StatelessWidget {
  const _FormSection({
    required this.label, required this.icon, required this.child,
    this.trailing,
  });
  final String label;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF1A1F2E) : AppColors.surface;
    final dividerColor = isDark ? const Color(0xFF3A4556) : AppColors.divider;
    final textSecondary = isDark ? const Color(0xFF8A92A3) : AppColors.textSecondary;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 15, color: textSecondary),
              const SizedBox(width: 6),
              Text(label.toUpperCase(),
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600,
                      color: textSecondary, letterSpacing: 0.6)),
              if (trailing != null) ...[
                const Spacer(),
                trailing!,
              ],
            ]),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

// ─── Alert Toggle Row ─────────────────────────────────────────────────────────
class _AlertRow extends StatelessWidget {
  const _AlertRow({
    required this.icon, required this.iconColor,
    required this.title, required this.subtitle,
    required this.value, required this.onChanged,
    this.showDivider = true,
  });
  final IconData icon;
  final Color iconColor;
  final String title, subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? const Color(0xFFE8EAED) : AppColors.textPrimary;
    final textSecondary = isDark ? const Color(0xFF8A92A3) : AppColors.textSecondary;
    final dividerColor = isDark ? const Color(0xFF3A4556) : AppColors.divider;

    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(isDark ? 0.15 : 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 17, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
                      color: textPrimary)),
              Text(subtitle,
                  style: TextStyle(fontSize: 11, color: textSecondary)),
            ],
          )),
          Transform.scale(
            scale: 0.85,
            child: Switch(value: value, onChanged: onChanged),
          ),
        ]),
      ),
      if (showDivider)
        Divider(height: 1, color: dividerColor),
    ]);
  }
}

// ─── Map Preview ──────────────────────────────────────────────────────────────
class _MapPreview extends StatelessWidget {
  const _MapPreview({required this.radius, this.lat, this.lng});
  final double radius;
  final double? lat;
  final double? lng;

  @override
  Widget build(BuildContext context) {
    final hasPoint = lat != null && lng != null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: 130,
        child: hasPoint ? _buildLiveMap() : _buildPlaceholder(),
      ),
    );
  }

  Widget _buildLiveMap() {
    final point = LatLng(lat!, lng!);
    final zoom = zoomForFenceRadius(radius);
    return Stack(
      children: [
        // IgnorePointer lets taps fall through to the picker-opening
        // GestureDetector; the key forces a recenter when the point or the
        // zoom bucket changes (not on every slider tick).
        IgnorePointer(
          child: FlutterMap(
            key: ValueKey('$lat,$lng,$zoom'),
            options: MapOptions(
              initialCenter: point,
              initialZoom: zoom,
              interactionOptions:
                  const InteractionOptions(flags: InteractiveFlag.none),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.Nap_Track.nap_track',
              ),
              CircleLayer(circles: [
                CircleMarker(
                  point: point,
                  radius: radius,
                  useRadiusInMeter: true,
                  color: AppColors.teal.withOpacity(0.15),
                  borderColor: AppColors.teal.withOpacity(0.6),
                  borderStrokeWidth: 1.5,
                ),
              ]),
              MarkerLayer(markers: [
                Marker(
                  point: point,
                  width: 30,
                  height: 30,
                  alignment: Alignment.topCenter,
                  child: const Icon(Icons.location_pin,
                      color: AppColors.crimson, size: 30),
                ),
              ]),
            ],
          ),
        ),
        const Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: EdgeInsets.all(8),
            child: Text('Tap to reposition pin',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ),
        ),
      ],
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFFEFF4F8),
      child: CustomPaint(
        painter: _MapPainter(radius: radius),
        child: const Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: EdgeInsets.all(8),
            child: Text('Tap to choose on map',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ),
        ),
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  const _MapPainter({required this.radius});
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final roadPaint = Paint()
      ..color = Colors.white.withOpacity(0.6)
      ..strokeCap = StrokeCap.round;

    // roads
    roadPaint.strokeWidth = 10;
    canvas.drawLine(Offset(0, size.height * 0.38),
        Offset(size.width, size.height * 0.44), roadPaint);
    roadPaint.strokeWidth = 7;
    canvas.drawLine(Offset(0, size.height * 0.72),
        Offset(size.width, size.height * 0.66), roadPaint);
    roadPaint.strokeWidth = 9;
    canvas.drawLine(Offset(size.width * 0.28, 0),
        Offset(size.width * 0.31, size.height), roadPaint);
    roadPaint.strokeWidth = 5;
    canvas.drawLine(Offset(size.width * 0.65, 0),
        Offset(size.width * 0.63, size.height), roadPaint);

    final cx = size.width * 0.58;
    final cy = size.height * 0.42;
    final r = (radius / 9).clamp(14.0, 52.0);

    // fence ring
    canvas.drawCircle(
      Offset(cx, cy), r,
      Paint()..color = AppColors.teal.withOpacity(0.1),
    );
    canvas.drawCircle(
      Offset(cx, cy), r,
      Paint()
        ..color = AppColors.teal.withOpacity(0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // pin glow
    canvas.drawCircle(
      Offset(cx, cy), 10,
      Paint()..color = AppColors.teal.withOpacity(0.2),
    );
    // pin dot
    canvas.drawCircle(
      Offset(cx, cy), 5,
      Paint()..color = AppColors.teal,
    );
  }

  @override
  bool shouldRepaint(_MapPainter old) => old.radius != radius;
}
