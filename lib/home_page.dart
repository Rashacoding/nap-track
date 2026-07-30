import 'package:flutter/material.dart';
import 'main.dart';
import 'alarm_set_page.dart';
import 'fence_manager.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PAGE 1 — Saved Alarms
// ═══════════════════════════════════════════════════════════════════════════
class AlarmsListPage extends StatefulWidget {
  final bool isDarkMode;
  final ValueChanged<bool> onThemeChanged;

  const AlarmsListPage({
    super.key,
    required this.isDarkMode,
    required this.onThemeChanged,
  });

  @override
  State<AlarmsListPage> createState() => _AlarmsListPageState();
}

class _AlarmsListPageState extends State<AlarmsListPage> with WidgetsBindingObserver {
  List<AlarmModel> _alarms = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAlarms();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadAlarms() async {
    final alarms = await AlarmStorage.loadAlarms();
    setState(() {
      _alarms = alarms;
      _isLoading = false;
    });
  }

  Future<void> _deleteAlarm(String alarmId) async {
    await AlarmStorage.deleteAlarm(alarmId);
    try {
      await FenceManager.unregister(alarmId);
    } catch (e) {
      debugPrint('Failed to remove geofence for $alarmId: $e');
    }
    await _loadAlarms();
  }

  Future<void> _toggleAlarmStatus(AlarmModel alarm) async {
    alarm.isActive = !alarm.isActive;
    await AlarmStorage.updateAlarmStatus(alarm.id, alarm.isActive);
    try {
      await FenceManager.sync(alarm);
    } catch (e) {
      debugPrint('Failed to sync geofence for ${alarm.id}: $e');
    }
    await _loadAlarms();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadAlarms();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('My alarms'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final active   = _alarms.where((a) => a.isActive).toList();
    final inactive = _alarms.where((a) => !a.isActive).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('My alarms'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.divider),
        ),
        actions: [
          // Theme toggle
          IconButton(
            icon: Icon(
              widget.isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              size: 20,
            ),
            onPressed: () => widget.onThemeChanged(!widget.isDarkMode),
            tooltip: widget.isDarkMode ? 'Light mode' : 'Dark mode',
          ),
        ],
      ),

      body: _alarms.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.alarm_off_rounded,
                      size: 64, color: AppColors.textSecondary.withOpacity(0.5)),
                  const SizedBox(height: 16),
                  Text('No alarms yet',
                      style: TextStyle(
                          fontSize: 16,
                          color: AppColors.textSecondary.withOpacity(0.7))),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              children: [
                // Active section
                _SectionHeader(label: 'Active', count: active.length),
                const SizedBox(height: 10),
                ...active.map((a) => _AlarmCard(
                  alarm: a,
                  onToggle: (_) => _toggleAlarmStatus(a),
                  onDelete: () => _deleteAlarm(a.id),
                  onTap: () {},
                )),

                const SizedBox(height: 20),

                // Inactive section
                _SectionHeader(label: 'Inactive', count: inactive.length),
                const SizedBox(height: 10),
                ...inactive.map((a) => _AlarmCard(
                  alarm: a,
                  onToggle: (_) => _toggleAlarmStatus(a),
                  onDelete: () => _deleteAlarm(a.id),
                  onTap: () {},
                )),

                const SizedBox(height: 24),
              ],
            ),

      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NewAlarmPage()),
                );
                await _loadAlarms();
              },
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Add new alarm'),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Section Header ───────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? const Color(0xFF8A92A3) : AppColors.textSecondary;
    
    return Row(children: [
      Text(label.toUpperCase(),
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600,
              color: textColor, letterSpacing: 0.8)),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF3A4556) : AppColors.divider,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text('$count',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                color: textColor)),
      ),
    ]);
  }
}

// ─── Alarm Card ───────────────────────────────────────────────────────────────
class _AlarmCard extends StatelessWidget {
  const _AlarmCard({
    required this.alarm,
    required this.onToggle,
    required this.onTap,
    required this.onDelete,
  });
  final AlarmModel alarm;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF1A1F2E) : AppColors.surface;
    final backgroundColor = isDark ? const Color(0xFF252D3D) : AppColors.background;
    final dividerColor = isDark ? const Color(0xFF3A4556) : AppColors.divider;
    final textPrimary = isDark ? const Color(0xFFE8EAED) : AppColors.textPrimary;
    final textSecondary = isDark ? const Color(0xFF8A92A3) : AppColors.textSecondary;

    final Color chipBg = alarm.isActive
        ? alarm.color.withOpacity(isDark ? 0.2 : 0.12)
        : backgroundColor;
    final Color chipFg = alarm.isActive ? alarm.color : textSecondary;

    return Dismissible(
      key: Key(alarm.id),
      direction: DismissDirection.endToStart,
      onDismissed: (direction) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20.0),
        decoration: BoxDecoration(
          color: AppColors.red.withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_sweep_rounded, color: AppColors.red, size: 28),
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: alarm.isActive
                  ? alarm.color.withOpacity(0.25)
                  : dividerColor,
            ),
            boxShadow: alarm.isActive
                ? [BoxShadow(color: alarm.color.withOpacity(0.08),
                blurRadius: 12, offset: const Offset(0, 4))]
                : [],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon badge
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: alarm.isActive
                        ? alarm.color.withOpacity(isDark ? 0.2 : 0.12)
                        : backgroundColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(alarm.icon,
                      size: 22,
                      color: alarm.isActive ? alarm.color : (isDark ? const Color(0xFF5A6370) : AppColors.textHint)),
                ),
                const SizedBox(width: 12),

                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(alarm.name,
                          style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600,
                            color: alarm.isActive ? textPrimary : textSecondary,
                          )),
                      const SizedBox(height: 2),
                      Text(alarm.route,
                          style: TextStyle(
                              fontSize: 12, color: textSecondary)),
                      const SizedBox(height: 10),

                      // Pills row
                      Wrap(spacing: 5, runSpacing: 5, children: [
                        _Pill(
                          icon: Icons.radar_rounded,
                          label: '${alarm.radius} m',
                          bg: chipBg, fg: chipFg,
                        ),
                        if (alarm.leadMinutes > 0)
                          _Pill(
                            icon: Icons.notifications_active_rounded,
                            label: '${alarm.leadMinutes} min early',
                            bg: AppColors.lime.withOpacity(isDark ? 0.25 : 0.4),
                            fg: isDark ? const Color(0xFF7EC98F) : const Color(0xFF3B6D11),
                          ),
                        if (!alarm.isActive)
                          _Pill(
                            icon: Icons.notifications_off_rounded,
                            label: 'Disabled',
                            bg: AppColors.red.withOpacity(isDark ? 0.15 : 0.1),
                            fg: isDark ? const Color(0xFFFF6B6B) : AppColors.red,
                          ),
                        ...alarm.alertTypes.map((t) => _Pill(
                          icon: t == 'Sound'
                              ? Icons.volume_up_rounded
                              : Icons.vibration_rounded,
                          label: t,
                          bg: backgroundColor,
                          fg: textSecondary,
                        )),
                        _Pill(
                          icon: Icons.audiotrack_rounded,
                          label: alarm.ringtoneName,
                          bg: AppColors.sky.withOpacity(isDark ? 0.2 : 0.12),
                          fg: alarm.isActive ? AppColors.sky : textSecondary,
                        ),
                      ]),
                    ],
                  ),
                ),

                // Toggle
                Transform.scale(
                  scale: 0.85,
                  child: Switch(
                    value: alarm.isActive,
                    onChanged: onToggle,
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

// ─── Pill Widget ──────────────────────────────────────────────────────────────
class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label,
    required this.bg, required this.fg});
  final IconData icon;
  final String label;
  final Color bg, fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withOpacity(0.2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: fg),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: fg)),
      ]),
    );
  }
}
