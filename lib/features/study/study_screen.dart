import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app_services.dart';
import '../../data/db/database.dart';
import '../../services/srs/srs_scheduler.dart';
import '../../theme.dart';
import '../editor/card_editor_screen.dart';
import 'flashcard_view.dart';
import 'study_controller.dart';

String _plural(int n, String word) => '$n ${n == 1 ? word : '${word}s'}';

class StudyScreen extends StatefulWidget {
  /// True when the Study tab is the visible tab.
  final bool active;

  /// Category to study, mirrored from the dictionary's filter (null = all).
  /// Applied whenever the Study tab becomes active; the in-screen chips can
  /// still override it for the current session.
  final int? catalogueId;
  const StudyScreen({super.key, required this.active, this.catalogueId});

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  StudyController? _ctrl;
  bool _revealed = false;
  // Default to a real flashcard: show ONE side as the prompt and hide the other
  // until "Show Answer". ("Show both" stays available in the menu for passive
  // review, but it must not be the default or the answer leaks on the front.)
  StudyDirection _direction = StudyDirection.englishToPolish;
  int? _studyCatId; // which category to study (null = all)

  /// Reload the queue for the currently-selected category.
  void _reload() {
    setState(() => _revealed = false);
    _ctrl?.load(catalogueId: _studyCatId);
  }

  @override
  void initState() {
    super.initState();
    _studyCatId = widget.catalogueId;
    SharedPreferences.getInstance().then((p) {
      final i = p.getInt('study_direction');
      if (i != null && mounted) {
        setState(() => _direction = StudyDirection.values[i]);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ctrl == null) {
      final s = AppServices.of(context);
      _ctrl = StudyController(s.db, s.srs);
      if (widget.active) _ctrl!.load(catalogueId: _studyCatId);
    }
  }

  @override
  void didUpdateWidget(covariant StudyScreen old) {
    super.didUpdateWidget(old);
    // Reload the due queue each time the Study tab becomes visible, so newly
    // imported/edited/deleted cards are reflected (and stale ones drop out).
    if (widget.active && !old.active) {
      // Re-sync to the dictionary's current category each time we open Study.
      setState(() => _studyCatId = widget.catalogueId);
      _reload();
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  Future<void> _setDirection(StudyDirection d) async {
    setState(() => _direction = d);
    final p = await SharedPreferences.getInstance();
    await p.setInt('study_direction', d.index);
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
          PopupMenuButton<StudyDirection>(
            icon: const Icon(Icons.swap_horiz),
            tooltip: 'Card direction',
            onSelected: _setDirection,
            itemBuilder: (_) => [
              _dirItem(StudyDirection.both, 'Show both'),
              _dirItem(StudyDirection.englishToPolish, 'English → Polish'),
              _dirItem(StudyDirection.polishToEnglish, 'Polish → English'),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload due cards',
            onPressed: _reload,
          ),
        ],
      ),
      body: Column(
        children: [
          // Pick which category to study (always visible so it can be changed
          // mid-session or after finishing one category).
          _StudyCategoryBar(
            db: services.db,
            selectedId: _studyCatId,
            onSelect: (id) {
              setState(() => _studyCatId = id);
              _reload();
            },
          ),
          Expanded(
            child: AnimatedBuilder(
              animation: ctrl,
              builder: (context, _) {
                if (ctrl.loading) {
                  return const Center(child: CircularProgressIndicator());
                }
                final card = ctrl.current;
                if (card == null) {
                  return _DoneView(
                      reviewed: ctrl.reviewed, onReload: _reload);
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
                        // SelectionArea makes the card's text highlightable and
                        // copyable (drag to select, then Ctrl/Cmd+C or
                        // right-click → Copy).
                        child: SelectionArea(
                          child: FlashcardView(
                            key: ValueKey(card.id),
                            card: card,
                            extraMeanings: ctrl.meaningsOf(card.id),
                            direction: _direction,
                            revealed: _revealed,
                            onReveal: () => setState(() => _revealed = true),
                            onSpeak: services.tts.speak,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Bottom action area: a single big "Show Answer" until revealed,
              // then the four grading buttons (keeps the thumb at the bottom).
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: _revealed
                    ? _GradeBar(
                        onGrade: (g) {
                          setState(() => _revealed = false);
                          ctrl.grade(g);
                        },
                        preview: (g) => ctrl.previewFor(card, g),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            icon: const Icon(Icons.visibility_outlined),
                            label: const Text('Show Answer',
                                style: TextStyle(fontSize: 16)),
                            onPressed: () => setState(() => _revealed = true),
                          ),
                        ),
                      ),
              ),
              _BottomLinks(
                canUndo: ctrl.canUndo,
                onUndo: () {
                  setState(() => _revealed = false);
                  ctrl.undo();
                },
                onEdit: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CardEditorScreen(cardId: card.id),
                    ),
                  );
                  setState(() => _revealed = false);
                  await ctrl.load(catalogueId: _studyCatId);
                },
              ),
              const SizedBox(height: 8),
            ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<StudyDirection> _dirItem(StudyDirection d, String label) {
    return PopupMenuItem(
      value: d,
      child: Row(
        children: [
          Icon(_direction == d ? Icons.check : Icons.swap_horiz,
              size: 18,
              color: _direction == d ? AppTheme.coral : AppTheme.muted),
          const SizedBox(width: 10),
          Text(label),
        ],
      ),
    );
  }
}

/// Horizontal "All / category" chips to choose which category to study.
/// Hidden when the user has no categories.
class _StudyCategoryBar extends StatelessWidget {
  final AppDatabase db;
  final int? selectedId;
  final ValueChanged<int?> onSelect;
  const _StudyCategoryBar(
      {required this.db, required this.selectedId, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Catalogue>>(
      stream: db.watchCatalogues(),
      builder: (context, snap) {
        final cats = snap.data ?? const <Catalogue>[];
        if (cats.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _pill('All', selectedId == null, () => onSelect(null)),
              for (final c in cats)
                _pill(c.name, selectedId == c.id, () => onSelect(c.id)),
            ],
          ),
        );
      },
    );
  }

  Widget _pill(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        labelStyle: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppTheme.ink),
        selectedColor: AppTheme.coral,
        backgroundColor: AppTheme.surface,
        side: BorderSide(color: selected ? AppTheme.coral : AppTheme.border),
      ),
    );
  }
}

class _BottomLinks extends StatelessWidget {
  final bool canUndo;
  final VoidCallback onUndo;
  final VoidCallback onEdit;
  const _BottomLinks(
      {required this.canUndo, required this.onUndo, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (canUndo)
          TextButton.icon(
            icon: const Icon(Icons.undo, size: 18),
            label: const Text('Undo'),
            onPressed: onUndo,
          ),
        TextButton.icon(
          icon: const Icon(Icons.edit, size: 18),
          label: const Text('Edit this card'),
          onPressed: onEdit,
        ),
      ],
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
          Text('${_plural(remaining, 'card')} due  ·  $reviewed reviewed',
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
      // Warm ramp in the Claude palette: neutral -> sand -> coral -> ink.
      child: Row(
        children: [
          _btn('Again', AppTheme.surface, AppTheme.ink,
              border: AppTheme.border, grade: ReviewGrade.again),
          _btn('Hard', AppTheme.sand, AppTheme.ink, grade: ReviewGrade.hard),
          _btn('Good', AppTheme.coral, Colors.white, grade: ReviewGrade.good),
          _btn('Easy', AppTheme.ink, Colors.white, grade: ReviewGrade.easy),
        ],
      ),
    );
  }

  Widget _btn(String label, Color bg, Color fg,
      {Color? border, required ReviewGrade grade}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: fg,
            padding: const EdgeInsets.symmetric(vertical: 12),
            elevation: 0,
            side: BorderSide(color: border ?? bg, width: 1),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: () => onGrade(grade),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(preview(grade),
                  style:
                      TextStyle(fontSize: 11, color: fg.withValues(alpha: 0.7))),
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
          const Icon(Icons.check_circle_outline, size: 56, color: AppTheme.coral),
          const SizedBox(height: 12),
          Text(reviewed == 0 ? 'No cards due right now' : 'Session complete!',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('${_plural(reviewed, 'card')} reviewed',
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
