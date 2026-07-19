import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../data/db/database.dart';
import '../../services/import_export/csv_export.dart';
import '../../services/import_export/download.dart';
import '../../theme.dart';

/// One group of entries sharing the same (normalized) English headword: the
/// single copy we keep, plus the ones marked for removal.
class _Group {
  final Flashcard keep;
  final List<Flashcard> remove;
  const _Group(this.keep, this.remove);
}

/// Finds obvious duplicates (same English term) and removes the least complete
/// copies — keeping the one with an image / the most filled-in fields. Shows a
/// full preview before anything is deleted, and supports Undo afterwards.
class DedupScreen extends StatefulWidget {
  const DedupScreen({super.key});

  @override
  State<DedupScreen> createState() => _DedupScreenState();
}

class _DedupScreenState extends State<DedupScreen> {
  bool _loaded = false;
  bool _loading = true;
  bool _busy = false;
  bool _done = false;
  List<_Group> _groups = [];
  List<Flashcard> _removed = []; // snapshot for undo + export

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _scan();
    }
  }

  String _key(Flashcard c) =>
      c.english.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Higher = keep. Prefers an image, then filled example/definition/note/tags,
  /// then study cards and a longer translation.
  int _score(Flashcard c) {
    var s = 0;
    final hasImg = c.imageBytes != null ||
        (c.imageUrl != null && c.imageUrl!.trim().isNotEmpty);
    if (hasImg) s += 1000;
    if ((c.exampleSentence ?? '').trim().isNotEmpty) s += 100;
    if ((c.englishDefinition ?? '').trim().isNotEmpty) s += 100;
    if ((c.note ?? '').trim().isNotEmpty) s += 50;
    if (c.tags.trim().isNotEmpty) s += 20;
    if (c.isCard) s += 10;
    s += c.polish.trim().length.clamp(0, 9);
    return s;
  }

  Future<void> _scan() async {
    final cards = await AppServices.of(context).db.allCards();
    final byKey = <String, List<Flashcard>>{};
    for (final c in cards) {
      byKey.putIfAbsent(_key(c), () => []).add(c);
    }
    final groups = <_Group>[];
    for (final entry in byKey.values) {
      if (entry.length < 2) continue;
      entry.sort((a, b) {
        final d = _score(b).compareTo(_score(a));
        return d != 0 ? d : a.id.compareTo(b.id); // tie: keep the older one
      });
      groups.add(_Group(entry.first, entry.sublist(1)));
    }
    groups.sort((a, b) =>
        a.keep.english.toLowerCase().compareTo(b.keep.english.toLowerCase()));
    if (!mounted) return;
    setState(() {
      _groups = groups;
      _loading = false;
    });
  }

  int get _removeCount =>
      _groups.fold(0, (n, g) => n + g.remove.length);

  Future<void> _remove() async {
    if (_busy) return;
    setState(() => _busy = true);
    final db = AppServices.of(context).db;
    final toRemove = [for (final g in _groups) ...g.remove];
    final ids = [for (final c in toRemove) c.id];
    // Snapshot full rows first so the delete can be undone.
    final snapshot = await db.getCards(ids);
    await db.deleteCards(ids);
    if (!mounted) return;
    setState(() {
      _removed = snapshot;
      _done = true;
      _busy = false;
    });
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      content: Text('Removed ${snapshot.length} duplicates'),
      action: SnackBarAction(
        label: 'Undo',
        textColor: Colors.white,
        onPressed: () async {
          await db.restoreCards(snapshot);
          if (mounted) Navigator.of(context).maybePop();
        },
      ),
    ));
  }

  void _exportList(List<Flashcard> cards, String name) {
    try {
      downloadText(name, cardsToCsv(cards));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved — check your downloads.')),
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Download is only available on the web app')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final showConfirm = !_loading && _groups.isNotEmpty && !_done;
    return Scaffold(
      appBar: AppBar(title: const Text('Find duplicates')),
      floatingActionButton: !showConfirm
          ? null
          : FloatingActionButton.extended(
              backgroundColor: const Color(0xFFB3261E),
              onPressed: _busy ? null : _remove,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.delete_sweep_outlined),
              label: Text('Remove $_removeCount'),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _groups.isEmpty
              ? _message('No duplicate entries found 🎉')
              : _done
                  ? _message('Removed ${_removed.length} duplicates.',
                      exportRemoved: true)
                  : _preview(),
    );
  }

  Widget _message(String msg, {bool exportRemoved = false}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline,
                  size: 56, color: AppTheme.coral),
              const SizedBox(height: 12),
              Text(msg,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 18),
              if (exportRemoved && _removed.isNotEmpty)
                OutlinedButton.icon(
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Export removed as CSV'),
                  onPressed: () => _exportList(
                      _removed, 'lexicon-removed-duplicates.csv'),
                ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Back to dictionary'),
              ),
            ],
          ),
        ),
      );

  Widget _preview() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: AppTheme.sand,
          padding: const EdgeInsets.all(14),
          child: Text(
            'Found ${_groups.length} duplicated ${_groups.length == 1 ? 'term' : 'terms'} '
            '— $_removeCount ${_removeCount == 1 ? 'copy' : 'copies'} to remove.\n'
            'For each term the most complete copy (image / filled fields) is kept; '
            'the emptier ones are removed. Nothing is deleted until you confirm, '
            'and it can be undone.',
            style: const TextStyle(fontSize: 13, height: 1.35),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 100),
            itemCount: _groups.length,
            itemBuilder: (context, i) {
              final g = _groups[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(g.keep.english,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      _line(Icons.check_circle, const Color(0xFF2E7D32),
                          'keep', g.keep),
                      for (final r in g.remove)
                        _line(Icons.remove_circle_outline,
                            const Color(0xFFB3261E), 'remove', r),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _line(IconData icon, Color color, String label, Flashcard c) {
    final hasImg = c.imageBytes != null ||
        (c.imageUrl != null && c.imageUrl!.trim().isNotEmpty);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text('$label — ${c.polish}',
                style: TextStyle(fontSize: 13.5, color: AppTheme.ink)),
          ),
          if (hasImg)
            const Icon(Icons.image, size: 14, color: AppTheme.muted),
        ],
      ),
    );
  }
}
