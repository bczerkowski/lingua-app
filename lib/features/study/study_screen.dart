import 'dart:typed_data';

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

/// Case-insensitive natural-order comparison so folder chips stay in a
/// predictable A–Z sequence (e.g. B2 before B10) regardless of creation order.
int _naturalCompare(String a, String b) {
  final re = RegExp(r'\d+|\D+');
  final pa = re.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final pb = re.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < pa.length && i < pb.length; i++) {
    final na = int.tryParse(pa[i]), nb = int.tryParse(pb[i]);
    final c = (na != null && nb != null)
        ? na.compareTo(nb)
        : pa[i].compareTo(pb[i]);
    if (c != 0) return c;
  }
  return pa.length.compareTo(pb.length);
}

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
    // Widen the study card on bigger screens instead of pinning it to a narrow
    // phone width — on a wide monitor 560px left huge empty margins.
    final screenW = MediaQuery.of(context).size.width;
    final double contentW = screenW < 620
        ? screenW
        : (screenW * 0.72).clamp(560.0, 880.0).toDouble();

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
                    reviewed: ctrl.reviewed,
                    lockedNew: ctrl.lockedNew,
                    onReload: _reload,
                    onLearnMore: () async {
                      await ctrl.learnMoreNew(10, catalogueId: _studyCatId);
                    },
                  );
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
                      constraints: BoxConstraints(maxWidth: contentW),
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
                constraints: BoxConstraints(maxWidth: contentW),
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

/// "All / category" chips to choose which category to study.
///
/// Collapsed (default): a single horizontally-scrolling row. Expanded: every
/// folder wrapped across rows so all are reachable on desktop, where a scroll
/// row hides folders past the screen edge. The expand toggle is pinned right.
/// Hidden when the user has no categories.
class _StudyCategoryBar extends StatefulWidget {
  final AppDatabase db;
  final int? selectedId;
  final ValueChanged<int?> onSelect;
  const _StudyCategoryBar(
      {required this.db, required this.selectedId, required this.onSelect});

  @override
  State<_StudyCategoryBar> createState() => _StudyCategoryBarState();
}

class _StudyCategoryBarState extends State<_StudyCategoryBar> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Catalogue>>(
      stream: widget.db.watchCatalogues(),
      builder: (context, snap) {
        final cats = snap.data ?? const <Catalogue>[];
        if (cats.isEmpty) return const SizedBox.shrink();

        final sorted = [...cats]
          ..sort((a, b) => _naturalCompare(a.name, b.name));
        final pills = <Widget>[
          _pill('All', widget.selectedId == null, () => widget.onSelect(null)),
          for (final c in sorted)
            _pill(
                c.icon != null && c.icon!.isNotEmpty
                    ? '${c.icon}  ${c.name}'
                    : c.name,
                widget.selectedId == c.id,
                () => widget.onSelect(c.id),
                avatarBytes: c.iconBytes),
        ];

        final toggle = IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          visualDensity: VisualDensity.compact,
          iconSize: 24,
          icon: Icon(_expanded
              ? Icons.expand_less_rounded
              : Icons.expand_more_rounded),
          color: AppTheme.coralDark,
          tooltip: _expanded ? 'Collapse folders' : 'Show all folders',
          onPressed: () => setState(() => _expanded = !_expanded),
        );

        if (_expanded) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 6, 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(spacing: 8, runSpacing: 8, children: pills),
                ),
                toggle,
              ],
            ),
          );
        }
        return SizedBox(
          height: 46,
          child: Row(
            children: [
              Expanded(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(left: 16, right: 4),
                  children: [
                    for (final p in pills)
                      Padding(
                          padding: const EdgeInsets.only(right: 8), child: p),
                  ],
                ),
              ),
              toggle,
            ],
          ),
        );
      },
    );
  }

  Widget _pill(String label, bool selected, VoidCallback onTap,
      {Uint8List? avatarBytes}) {
    return ChoiceChip(
      label: Text(label),
      avatar: avatarBytes == null
          ? null
          : ClipOval(
              child: Image.memory(avatarBytes,
                  width: 20, height: 20, fit: BoxFit.cover)),
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
  final int lockedNew;
  final VoidCallback onReload;
  final VoidCallback onLearnMore;
  const _DoneView({
    required this.reviewed,
    required this.lockedNew,
    required this.onReload,
    required this.onLearnMore,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline,
                size: 56, color: AppTheme.coral),
            const SizedBox(height: 12),
            Text(reviewed == 0 ? 'No cards due right now' : 'Session complete!',
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('${_plural(reviewed, 'card')} reviewed',
                style: TextStyle(color: Colors.grey.shade600)),
            if (lockedNew > 0) ...[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.sand,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      'Daily new-card limit reached.\n'
                      '$lockedNew new ${lockedNew == 1 ? 'card is' : 'cards are'} '
                      'waiting for the coming days.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, height: 1.35),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      icon: const Icon(Icons.add, size: 20),
                      label: Text('Learn ${lockedNew < 10 ? lockedNew : 10} '
                          'more now'),
                      onPressed: onLearnMore,
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Check again'),
              onPressed: onReload,
            ),
          ],
        ),
      ),
    );
  }
}
