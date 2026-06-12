import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../services/srs/srs_scheduler.dart';
import '../editor/card_editor_screen.dart';
import 'flashcard_view.dart';
import 'study_controller.dart';

class StudyScreen extends StatefulWidget {
  const StudyScreen({super.key});

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  StudyController? _ctrl;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ctrl == null) {
      final s = AppServices.of(context);
      _ctrl = StudyController(s.db, s.srs)..load();
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    final ctrl = _ctrl!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Study'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload due cards',
            onPressed: () => ctrl.load(),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: ctrl,
        builder: (context, _) {
          if (ctrl.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          final card = ctrl.current;
          if (card == null) {
            return _DoneView(reviewed: ctrl.reviewed, onReload: ctrl.load);
          }
          return Column(
            children: [
              _ProgressBar(remaining: ctrl.remaining, reviewed: ctrl.reviewed),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: SingleChildScrollView(
                        child: FlashcardView(
                          key: ValueKey(card.id),
                          card: card,
                          onSpeak: services.tts.speak,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _GradeBar(
                onGrade: ctrl.grade,
                preview: (g) => ctrl.previewFor(card, g),
              ),
              TextButton.icon(
                icon: const Icon(Icons.edit, size: 18),
                label: const Text('Edit this card'),
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CardEditorScreen(cardId: card.id),
                    ),
                  );
                  await ctrl.load();
                },
              ),
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final int remaining;
  final int reviewed;
  const _ProgressBar({required this.remaining, required this.reviewed});

  @override
  Widget build(BuildContext context) {
    final total = remaining + reviewed;
    final value = total == 0 ? 0.0 : reviewed / total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        children: [
          LinearProgressIndicator(
            value: value,
            minHeight: 6,
            borderRadius: BorderRadius.circular(6),
          ),
          const SizedBox(height: 6),
          Text('$remaining due  ·  $reviewed reviewed',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        ],
      ),
    );
  }
}

class _GradeBar extends StatelessWidget {
  final void Function(ReviewGrade) onGrade;
  final String Function(ReviewGrade) preview;
  const _GradeBar({required this.onGrade, required this.preview});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _btn(context, 'Again', Colors.red, ReviewGrade.again),
          _btn(context, 'Hard', Colors.orange, ReviewGrade.hard),
          _btn(context, 'Good', Colors.green, ReviewGrade.good),
          _btn(context, 'Easy', Colors.blue, ReviewGrade.easy),
        ],
      ),
    );
  }

  Widget _btn(BuildContext context, String label, Color color, ReviewGrade g) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          onPressed: () => onGrade(g),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(preview(g),
                  style: const TextStyle(fontSize: 11, color: Colors.white70)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DoneView extends StatelessWidget {
  final int reviewed;
  final VoidCallback onReload;
  const _DoneView({required this.reviewed, required this.onReload});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.celebration, size: 56, color: Colors.green),
          const SizedBox(height: 12),
          Text(reviewed == 0 ? 'No cards due right now' : 'Session complete!',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('$reviewed cards reviewed',
              style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('Check again'),
            onPressed: onReload,
          ),
        ],
      ),
    );
  }
}
