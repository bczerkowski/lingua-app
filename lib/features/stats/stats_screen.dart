import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../data/db/database.dart';
import '../../theme.dart';
import '../study/study_controller.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  Future<({DeckStats stats, int streak})> _load(AppDatabase db) async {
    final stats = await db.deckStats();
    final streak = await readStudyStreak();
    return (stats: stats, streak: streak);
  }

  @override
  Widget build(BuildContext context) {
    final db = AppServices.of(context).db;
    return Scaffold(
      appBar: AppBar(title: const Text('Statistics')),
      body: FutureBuilder<({DeckStats stats, int streak})>(
        future: _load(db),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final s = snap.data!.stats;
          final streak = snap.data!.streak;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _StatTile(
                icon: Icons.local_fire_department_rounded,
                value: streak == 0 ? '—' : '$streak ${streak == 1 ? 'day' : 'days'}',
                label: 'Current streak',
                accent: true,
              ),
              _StatTile(
                icon: Icons.bolt_rounded,
                value: '${s.dueToday}',
                label: 'Cards due today',
              ),
              _StatTile(
                icon: Icons.school_rounded,
                value: '${s.learned}',
                label: 'Cards learned',
              ),
              _StatTile(
                icon: Icons.trending_up_rounded,
                value: '${s.difficult}',
                label: 'Difficult cards (lapsed at least once)',
              ),
              _StatTile(
                icon: Icons.style_rounded,
                value: '${s.total}',
                label: 'Total study cards',
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final bool accent;
  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: BoxDecoration(
        color: accent ? AppTheme.coral.withValues(alpha: 0.10) : AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: accent ? AppTheme.coral : AppTheme.border,
            width: accent ? 1.4 : 1),
      ),
      child: Row(
        children: [
          Icon(icon, size: 30, color: accent ? AppTheme.coralDark : AppTheme.ink),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(label,
                    style: const TextStyle(
                        fontSize: 14, color: AppTheme.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
