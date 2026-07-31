import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:just_audio/just_audio.dart';
import 'package:vibration/vibration.dart';

import 'alarm_notifications.dart';
import 'main.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PAGE — Alarm ringing
//
// Shown when the app is opened by an arrival notification (full-screen
// intent, tapping the notification body, or a snooze firing again). Owns the
// actual looping ringtone + vibration — the notification itself only gets a
// single OS-level chime, since Android locks a channel's sound/vibration
// settings in at first creation and won't honor per-alarm changes after that.
// ═══════════════════════════════════════════════════════════════════════════
class AlarmRingPage extends StatefulWidget {
  const AlarmRingPage({super.key, required this.payload});

  final AlarmPayload payload;

  @override
  State<AlarmRingPage> createState() => _AlarmRingPageState();
}

class _AlarmRingPageState extends State<AlarmRingPage>
    with SingleTickerProviderStateMixin {
  final _player = AudioPlayer();
  late final AnimationController _pulse;
  StreamSubscription<NotificationResponse>? _responseSub;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _startRinging();

    // If Stop/Snooze is tapped from the notification tray instead of the
    // buttons below (this screen stays open behind it), stay in sync so the
    // ringtone/vibration don't keep going after the notification is gone.
    _responseSub = alarmResponses.stream.listen((response) {
      if (response.actionId == null) return;
      final payload = AlarmPayload.decode(response.payload);
      if (payload?.id != widget.payload.id) return;
      if (response.actionId == actionSnooze) {
        _onSnooze(alreadyHandled: true);
      } else {
        _onStop(alreadyHandled: true);
      }
    });
  }

  Future<void> _startRinging() async {
    if (widget.payload.vibrateOn) {
      _startVibrating();
    }
    if (widget.payload.soundOn) {
      await _startAudio();
    }
  }

  Future<void> _startVibrating() async {
    if (!await Vibration.hasVibrator()) return;
    // Off, on, off, on… repeats from index 0 forever until Vibration.cancel().
    unawaited(Vibration.vibrate(
      pattern: [0, 700, 400, 700, 400],
      repeat: 0,
    ));
  }

  Future<void> _startAudio() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.sonification,
          usage: AndroidAudioUsage.alarm,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        avAudioSessionCategory: AVAudioSessionCategory.playback,
      ));
      await session.setActive(true);

      final uri = widget.payload.ringtoneUri;
      final isPlayableUri =
          uri.startsWith('content://') || uri.startsWith('/');
      if (isPlayableUri) {
        await _player.setAudioSource(
          AudioSource.uri(
            uri.startsWith('/') ? Uri.file(uri) : Uri.parse(uri),
          ),
        );
      } else {
        // No real ringtone selected (empty, or one of the mock picker
        // entries that isn't a playable URI) — fall back to the bundled
        // alarm tone rather than staying silent.
        await _player.setAudioSource(
          AudioSource.asset('assets/sounds/alarm_default.wav'),
        );
      }
      await _player.setLoopMode(LoopMode.one);
      await _player.setVolume(1.0);
      await _player.play();
    } catch (e) {
      debugPrint('Alarm ringtone playback failed, using fallback tone: $e');
      try {
        await _player.setAudioSource(
          AudioSource.asset('assets/sounds/alarm_default.wav'),
        );
        await _player.setLoopMode(LoopMode.one);
        await _player.play();
      } catch (e2) {
        debugPrint('Fallback alarm tone also failed: $e2');
      }
    }
  }

  Future<void> _stopRinging() async {
    await Vibration.cancel();
    await _player.stop();
  }

  // [alreadyHandled] is true when this was triggered by a notification-tray
  // action tap: the response handler in alarm_notifications.dart has already
  // cancelled/rescheduled the OS notification, so only the in-app ringing
  // loop and the screen itself still need to be torn down.
  Future<void> _onStop({bool alreadyHandled = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    await _stopRinging();
    if (!alreadyHandled) await cancelAlarm(widget.payload.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _onSnooze({bool alreadyHandled = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    await _stopRinging();
    if (!alreadyHandled) {
      await cancelAlarm(widget.payload.id);
      await scheduleSnooze(widget.payload);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Snoozed — ringing again in ${snoozeDuration.inMinutes} min')),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _responseSub?.cancel();
    Vibration.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F1419),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              children: [
                const Spacer(),
                ScaleTransition(
                  scale: Tween(begin: 0.92, end: 1.08).animate(
                    CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
                  ),
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.teal.withOpacity(0.15),
                      border: Border.all(color: AppColors.teal, width: 2),
                    ),
                    child: const Icon(Icons.alarm_rounded,
                        color: AppColors.teal, size: 56),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  widget.payload.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.payload.body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF8A92A3),
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _busy ? null : _onSnooze,
                    icon: const Icon(Icons.snooze_rounded),
                    label: Text(
                        'Snooze ${snoozeDuration.inMinutes} min'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF252D3D),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _busy ? null : _onStop,
                    icon: const Icon(Icons.stop_circle_rounded),
                    label: const Text('Stop'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.danger,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
