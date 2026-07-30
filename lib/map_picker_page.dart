import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'main.dart';

/// A zoom level that keeps a fence circle of the given radius visible.
double zoomForFenceRadius(double radiusMeters) {
  if (radiusMeters <= 300) return 15;
  if (radiusMeters <= 1000) return 14;
  if (radiusMeters <= 2500) return 12.5;
  if (radiusMeters <= 5000) return 11.5;
  return 10.5;
}

/// The result returned by [MapPickerPage].
class MapPickResult {
  final double latitude;
  final double longitude;
  final String label;

  const MapPickResult({
    required this.latitude,
    required this.longitude,
    required this.label,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Full-screen map destination picker — tap to drop the pin.
// ═══════════════════════════════════════════════════════════════════════════
class MapPickerPage extends StatefulWidget {
  const MapPickerPage({
    super.key,
    this.initialLat,
    this.initialLng,
    required this.radiusMeters,
  });

  final double? initialLat;
  final double? initialLng;
  final double radiusMeters;

  @override
  State<MapPickerPage> createState() => _MapPickerPageState();
}

class _MapPickerPageState extends State<MapPickerPage> {
  final _mapController = MapController();

  LatLng? _picked;
  String? _pickedLabel;
  bool _resolvingLabel = false;
  bool _locating = false;

  // Fallback view when nothing is picked and GPS is unavailable (Colombo).
  static const _fallbackCenter = LatLng(6.9271, 79.8612);

  @override
  void initState() {
    super.initState();
    if (widget.initialLat != null && widget.initialLng != null) {
      _picked = LatLng(widget.initialLat!, widget.initialLng!);
      _resolveLabel(_picked!);
    } else {
      // Best effort: start the map near the user.
      _centerOnUser(moveOnly: true);
    }
  }

  Future<void> _resolveLabel(LatLng point) async {
    setState(() {
      _resolvingLabel = true;
      _pickedLabel = null;
    });
    String label =
        '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
    try {
      final placemarks =
          await geo.placemarkFromCoordinates(point.latitude, point.longitude);
      final p = placemarks.firstOrNull;
      if (p != null) {
        final parts = [p.name, p.street, p.locality]
            .where((s) => s != null && s.isNotEmpty)
            .cast<String>()
            .toList();
        // Drop duplicates like name == street.
        final seen = <String>{};
        final unique = parts.where(seen.add).take(2).join(', ');
        if (unique.isNotEmpty) label = unique;
      }
    } catch (_) {
      // Keep coordinate label; reverse geocoding needs network.
    }
    if (mounted) {
      setState(() {
        _pickedLabel = label;
        _resolvingLabel = false;
      });
    }
  }

  void _onTap(TapPosition tapPosition, LatLng point) {
    setState(() => _picked = point);
    _resolveLabel(point);
  }

  Future<void> _centerOnUser({bool moveOnly = false}) async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      final here = LatLng(pos.latitude, pos.longitude);
      _mapController.move(here, 15);
      if (!moveOnly) {
        setState(() => _picked = here);
        _resolveLabel(here);
      }
    } catch (e) {
      debugPrint('Could not get current location: $e');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _confirm() {
    final picked = _picked;
    if (picked == null) return;
    Navigator.pop(
      context,
      MapPickResult(
        latitude: picked.latitude,
        longitude: picked.longitude,
        label: _pickedLabel ??
            '${picked.latitude.toStringAsFixed(5)}, ${picked.longitude.toStringAsFixed(5)}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF1A1F2E) : AppColors.surface;
    final textPrimary = isDark ? const Color(0xFFE8EAED) : AppColors.textPrimary;
    final textSecondary =
        isDark ? const Color(0xFF8A92A3) : AppColors.textSecondary;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Choose destination'),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _picked ?? _fallbackCenter,
              initialZoom: _picked != null
                  ? zoomForFenceRadius(widget.radiusMeters)
                  : 12,
              onTap: _onTap,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.Nap_Track.nap_track',
              ),
              if (_picked != null) ...[
                CircleLayer(circles: [
                  CircleMarker(
                    point: _picked!,
                    radius: widget.radiusMeters,
                    useRadiusInMeter: true,
                    color: AppColors.teal.withOpacity(0.15),
                    borderColor: AppColors.teal.withOpacity(0.6),
                    borderStrokeWidth: 2,
                  ),
                ]),
                MarkerLayer(markers: [
                  Marker(
                    point: _picked!,
                    width: 40,
                    height: 40,
                    alignment: Alignment.topCenter,
                    child: const Icon(Icons.location_pin,
                        color: AppColors.crimson, size: 40),
                  ),
                ]),
              ],
            ],
          ),

          // My-location button
          Positioned(
            right: 16,
            bottom: 130,
            child: FloatingActionButton(
              heroTag: 'map_picker_my_location',
              backgroundColor: surfaceColor,
              foregroundColor: AppColors.teal,
              onPressed: _centerOnUser,
              child: _locating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.teal),
                    )
                  : const Icon(Icons.my_location_rounded),
            ),
          ),

          // Bottom confirm card
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.location_on_rounded,
                          color: AppColors.teal, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _picked == null
                            ? Text('Tap the map to drop your destination pin',
                                style: TextStyle(
                                    fontSize: 13, color: textSecondary))
                            : _resolvingLabel
                                ? Text('Finding address…',
                                    style: TextStyle(
                                        fontSize: 13, color: textSecondary))
                                : Text(_pickedLabel ?? '',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: textPrimary)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _picked == null ? null : _confirm,
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Set destination'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
