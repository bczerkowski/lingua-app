import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app_services.dart';
import '../../data/db/database.dart';
import '../../data/seed.dart';
import '../../services/import_export/csv_import.dart';
import '../../theme.dart';
import '../catalogues/catalogue_screen.dart';
import '../editor/card_editor_screen.dart';

class DictionaryScreen extends StatefulWidget {
  final VoidCallback onStudyTap;
  const DictionaryScreen({super.key, required this.onStudyTap});

  @override
  State<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends State<DictionaryScreen> {
  String _query = '';
  bool _selectMode = false;
  bool _alphabetical = false;
  bool _groupByCategory = false;
  int? _filterCatId;
  final Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    // Restore the user's view preferences from the last session.
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        _alphabetical = p.getBool('pref_alpha') ?? false;
        _groupByCategory = p.getBool('pref_group') ?? false;
      });
    });
  }

  Future<void> _savePrefs() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('pref_alpha', _alphabetical);
    await p.setBool('pref_group', _groupByCategory);
  }

  void _enterSelect([int? first]) {
    setState(() {
      _selectMode = true;
      if (first != null) _selected.add(first);
    });
  }

  void _exitSelect() {
    setState(() {
      _selectMode = false;
      _selected.clear();
    });
  }

  void _toggle(int id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
      if (_selected.isEmpty) _selectMode = false;
    });
  }

  Future<void> _deleteSelected(AppDatabase db) async {
    final count = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $count ${count == 1 ? 'entry' : 'entries'}?'),
        content: const Text('This permanently removes them and cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB3261E)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;

    // Snapshot the rows first so the delete can be undone.
    final ids = _selected.toList();
    final removed = await db.getCards(ids);
    await db.deleteCards(ids);
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Deleted $count ${count == 1 ? 'entry' : 'entries'}'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Undo',
          textColor: Colors.white,
          onPressed: () => db.restoreCards(removed),
        ),
      ),
    );
    _exitSelect();
  }

  /// Produces a flat render list: section-header strings (when grouping) mixed
  /// with [Flashcard]s, applying alphabetical sort (by English) when enabled.
  List<Object> _buildRows(List<Flashcard> items, Map<int, String> names) {
    int byEnglish(Flashcard a, Flashcard b) =>
        a.english.toLowerCase().compareTo(b.english.toLowerCase());

    final list = [...items];
    if (_alphabetical) list.sort(byEnglish);
    if (!_groupByCategory) return list;

    final groups = <int?, List<Flashcard>>{};
    for (final c in list) {
      groups.putIfAbsent(c.catalogueId, () => []).add(c);
    }
    final keys = groups.keys.toList()
      ..sort((a, b) {
        if (a == null) return 1; // Uncategorized last
        if (b == null) return -1;
        return (names[a] ?? '')
            .toLowerCase()
            .compareTo((names[b] ?? '').toLowerCase());
      });

    final rows = <Object>[];
    for (final k in keys) {
      rows.add(k == null ? 'Uncategorized' : (names[k] ?? 'Category'));
      rows.addAll(groups[k]!);
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    final db = services.db;

    return Scaffold(
      floatingActionButton: _selectMode
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openEditor(context, null),
              icon: const Icon(Icons.add, size: 24),
              label: const Text('New entry', style: TextStyle(fontSize: 16)),
            ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(db: db, onStudyTap: widget.onStudyTap),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: TextField(
                style: const TextStyle(fontSize: 17),
                decoration: const InputDecoration(
                  hintText: 'Search in Polish or English…',
                  prefixIcon: Icon(Icons.search, size: 24),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<Flashcard>>(
                stream: db.searchEntries(_query),
                builder: (context, snap) {
                  final items = snap.data ?? const <Flashcard>[];
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (items.isEmpty) {
                    return Center(
                      child: Text('No matching entries.',
                          style: TextStyle(fontSize: 16, color: AppTheme.muted)),
                    );
                  }
                  final filtered = _filterCatId == null
                      ? items
                      : items
                          .where((c) => c.catalogueId == _filterCatId)
                          .toList();
                  return Column(
                    children: [
                      _ActionBar(
                        selectMode: _selectMode,
                        selectedCount: _selected.length,
                        totalCount: filtered.length,
                        allSelected: filtered.isNotEmpty &&
                            _selected.length == filtered.length,
                        alphabetical: _alphabetical,
                        groupByCategory: _groupByCategory,
                        onToggleSort: () {
                          setState(() => _alphabetical = !_alphabetical);
                          _savePrefs();
                        },
                        onToggleGroup: () {
                          setState(
                              () => _groupByCategory = !_groupByCategory);
                          _savePrefs();
                        },
                        onEnterSelect: () => _enterSelect(),
                        onCancel: _exitSelect,
                        onToggleAll: () => setState(() {
                          if (_selected.length == filtered.length) {
                            _selected.clear();
                            _selectMode = false;
                          } else {
                            _selected
                              ..clear()
                              ..addAll(filtered.map((e) => e.id));
                          }
                        }),
                        onDelete: () => _deleteSelected(db),
                      ),
                      if (!_selectMode)
                        _CategoryFilterBar(
                          db: db,
                          selectedId: _filterCatId,
                          onSelect: (id) => setState(() => _filterCatId = id),
                        ),
                      Expanded(
                        child: StreamBuilder<List<Catalogue>>(
                          stream: db.watchCatalogues(),
                          builder: (context, catSnap) {
                            final names = <int, String>{
                              for (final c
                                  in (catSnap.data ?? const <Catalogue>[]))
                                c.id: c.name
                            };
                            if (filtered.isEmpty) {
                              return Center(
                                child: Text('No entries in this category.',
                                    style: TextStyle(
                                        fontSize: 16, color: AppTheme.muted)),
                              );
                            }
                            final rows = _buildRows(filtered, names);
                            return ListView.builder(
                              padding: const EdgeInsets.fromLTRB(20, 4, 20, 110),
                              itemCount: rows.length,
                              itemBuilder: (context, i) {
                                final row = rows[i];
                                if (row is String) return _SectionHeader(row);
                                final card = row as Flashcard;
                                return _EntryRow(
                                  card: card,
                                  services: services,
                                  db: db,
                                  selectMode: _selectMode,
                                  selected: _selected.contains(card.id),
                                  onTap: () {
                                    if (_selectMode) {
                                      _toggle(card.id);
                                    } else {
                                      _openEditor(context, card.id);
                                    }
                                  },
                                  onLongPress: () => _enterSelect(card.id),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openEditor(BuildContext context, int? cardId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CardEditorScreen(cardId: cardId)),
    );
  }
}

/// Either a "Select" entry point, or the multi-select toolbar (count, select
/// all, delete, cancel).
class _ActionBar extends StatelessWidget {
  final bool selectMode;
  final int selectedCount;
  final int totalCount;
  final bool allSelected;
  final bool alphabetical;
  final bool groupByCategory;
  final VoidCallback onToggleSort;
  final VoidCallback onToggleGroup;
  final VoidCallback onEnterSelect;
  final VoidCallback onCancel;
  final VoidCallback onToggleAll;
  final VoidCallback onDelete;
  const _ActionBar({
    required this.selectMode,
    required this.selectedCount,
    required this.totalCount,
    required this.allSelected,
    required this.alphabetical,
    required this.groupByCategory,
    required this.onToggleSort,
    required this.onToggleGroup,
    required this.onEnterSelect,
    required this.onCancel,
    required this.onToggleAll,
    required this.onDelete,
  });

  Widget _chip(String label, IconData icon, bool selected, VoidCallback onTap) {
    return FilterChip(
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      avatar: Icon(icon,
          size: 16, color: selected ? Colors.white : AppTheme.ink),
      label: Text(label),
      labelStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: selected ? Colors.white : AppTheme.ink),
      backgroundColor: AppTheme.surface,
      selectedColor: AppTheme.coral,
      side: BorderSide(color: selected ? AppTheme.coral : AppTheme.border),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!selectMode) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 10, 4),
        child: Row(
          children: [
            _chip('A–Z', Icons.sort_by_alpha, alphabetical, onToggleSort),
            const SizedBox(width: 8),
            _chip('Group', Icons.folder_outlined, groupByCategory,
                onToggleGroup),
            const Spacer(),
            IconButton(
              onPressed: onEnterSelect,
              icon: const Icon(Icons.checklist_rounded),
              tooltip: 'Select',
            ),
          ],
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.sand,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onCancel,
            icon: const Icon(Icons.close),
            tooltip: 'Cancel',
          ),
          Expanded(
            child: Text('$selectedCount selected',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: onToggleAll,
            child: Text(allSelected ? 'Clear all' : 'Select all',
                style: const TextStyle(fontSize: 15)),
          ),
          const SizedBox(width: 4),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB3261E),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onPressed: selectedCount == 0 ? null : onDelete,
            icon: const Icon(Icons.delete_outline, size: 20),
            label: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

/// Horizontal "All / category" chips to filter the list by category.
/// Hidden when the user has no categories yet.
class _CategoryFilterBar extends StatelessWidget {
  final AppDatabase db;
  final int? selectedId;
  final ValueChanged<int?> onSelect;
  const _CategoryFilterBar(
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
            padding: const EdgeInsets.symmetric(horizontal: 18),
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

/// A category section header shown when grouping is enabled.
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 0, 8),
      child: Row(
        children: [
          const Icon(Icons.folder_rounded, size: 16, color: AppTheme.coralDark),
          const SizedBox(width: 7),
          Text(title.toUpperCase(),
              style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: AppTheme.coralDark)),
        ],
      ),
    );
  }
}

/// A rich dictionary row: target line, example sentence, and a tag strip
/// (part of speech, gender, topics). In select mode it shows a checkbox.
class _EntryRow extends StatelessWidget {
  final Flashcard card;
  final AppServices services;
  final AppDatabase db;
  final bool selectMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _EntryRow({
    required this.card,
    required this.services,
    required this.db,
    required this.selectMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final allTags = card.tags
        .split(';')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    final pos = allTags.isNotEmpty ? allTags.first : null;
    final topics = allTags.length > 1 ? allTags.sublist(1) : <String>[];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: selected ? const Color(0xFFFBEEE8) : AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected ? AppTheme.coral : AppTheme.border,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (selectMode) ...[
                  Icon(
                    selected
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    color: selected ? AppTheme.coral : AppTheme.muted,
                    size: 28,
                  ),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _targetLine(),
                      if (card.exampleSentence != null) ...[
                        const SizedBox(height: 6),
                        Text('“${card.exampleSentence}”',
                            style: const TextStyle(
                                fontSize: 15,
                                height: 1.3,
                                fontStyle: FontStyle.italic,
                                color: Color(0xFF55524B))),
                      ],
                      const SizedBox(height: 10),
                      _tagStrip(pos, topics),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (!selectMode) _addButton(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _targetLine() {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // English is the headword (shown first), Polish is the translation.
        Text(card.english,
            style: GoogleFonts.sourceSerif4(
                fontSize: 21,
                fontWeight: FontWeight.w600,
                color: Colors.black)),
        InkWell(
          onTap: () => services.tts.speak(card.english, 'en-US'),
          customBorder: const CircleBorder(),
          child: const Padding(
            padding: EdgeInsets.all(3),
            child: Icon(Icons.volume_up_rounded, size: 19, color: AppTheme.muted),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text('·', style: TextStyle(fontSize: 19, color: AppTheme.muted)),
        ),
        Text(card.polish,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w500, color: Colors.black)),
      ],
    );
  }

  Widget _tagStrip(String? pos, List<String> topics) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (pos != null) _posPill(pos),
        for (final t in topics) _topicPill(t),
      ],
    );
  }

  Widget _posPill(String pos) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.sand,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(pos.toUpperCase(),
            style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: Color(0xFF55524B))),
      );

  Widget _topicPill(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: AppTheme.border),
        ),
        child: Text('#$t',
            style: const TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w500, color: AppTheme.muted)),
      );

  Widget _addButton(BuildContext context) {
    if (card.isCard) {
      return Container(
        width: 54,
        height: 54,
        decoration: const BoxDecoration(
          color: AppTheme.coral,
          shape: BoxShape.circle,
        ),
        child: const Tooltip(
          message: 'In study deck',
          child: Icon(Icons.check_rounded, color: Colors.white, size: 28),
        ),
      );
    }
    return Material(
      color: AppTheme.coral,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () async {
          await db.promoteToCard(card.id);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Added to study deck')),
            );
          }
        },
        child: const SizedBox(
          width: 54,
          height: 54,
          child: Tooltip(
            message: 'Add to study deck',
            child: Icon(Icons.add_rounded, color: Colors.white, size: 30),
          ),
        ),
      ),
    );
  }
}

/// Overflow menu with self-service data recovery actions.
class _ManageMenu extends StatelessWidget {
  final AppDatabase db;
  const _ManageMenu({required this.db});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: AppTheme.muted),
      tooltip: 'Manage data',
      onSelected: (v) {
        if (v == 'categories') {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CatalogueScreen()),
          );
        }
        if (v == 'import') _importCsv(context);
        if (v == 'reset') _confirmReset(context);
        if (v == 'clear') _confirmClear(context);
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'categories',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.folder_outlined),
            title: Text('Manage categories'),
          ),
        ),
        PopupMenuItem(
          value: 'import',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.upload_file_outlined),
            title: Text('Import from CSV'),
          ),
        ),
        PopupMenuItem(
          value: 'reset',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.restart_alt),
            title: Text('Reset to sample deck'),
          ),
        ),
        PopupMenuItem(
          value: 'clear',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_sweep_outlined),
            title: Text('Delete all entries'),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmReset(BuildContext context) async {
    final ok = await _confirm(context, 'Reset to sample deck?',
        'This removes your current entries and restores the original sample deck.');
    if (ok != true) return;
    await Seeder(db).reset();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Restored the sample deck')),
      );
    }
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await _confirm(context, 'Delete all entries?',
        'This permanently removes every entry. This cannot be undone.');
    if (ok != true) return;
    await db.clearAllCards();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All entries deleted')),
      );
    }
  }

  Future<bool?> _confirm(BuildContext context, String title, String body) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirm')),
        ],
      ),
    );
  }

  Future<void> _importCsv(BuildContext context) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.single;
    final bytes = file.bytes;
    if (bytes == null || !context.mounted) return;

    final importer = CsvImporter(db);
    final entries = importer.parse(bytes);
    if (entries.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No entries found in that file')),
        );
      }
      return;
    }

    // Suggest a category name derived from the file (Quizlet: "set-<id>-name").
    final suggested = file.name
        .replaceAll(RegExp(r'\.csv$', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^set-\d+-'), '')
        .replaceAll(RegExp(r'[-_]+'), ' ')
        .trim();

    if (!context.mounted) return;
    final ctrl = TextEditingController(text: suggested);
    final confirmed = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Import ${entries.length} entries'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Add them to a category (leave blank for none):'),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                hintText: 'Category name',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Import')),
        ],
      ),
    );
    if (confirmed == null) return; // cancelled

    int? catId;
    final name = confirmed.trim();
    if (name.isNotEmpty) catId = await db.createCatalogue(name);
    final n = await importer.insertAll(entries, catalogueId: catId);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported $n ${n == 1 ? 'card' : 'cards'}')),
      );
    }
  }
}

/// Eyebrow label, serif title, and a live "cards due — study now" link.
class _Header extends StatelessWidget {
  final AppDatabase db;
  final VoidCallback onStudyTap;
  const _Header({required this.db, required this.onStudyTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('SŁOWNIK · DICTIONARY',
                    style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.8,
                        color: AppTheme.muted)),
              ),
              _ManageMenu(db: db),
            ],
          ),
          Text('Lexicon',
              style: GoogleFonts.sourceSerif4(
                  fontSize: 38,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5,
                  color: AppTheme.ink)),
          const SizedBox(height: 6),
          StreamBuilder<int>(
            stream: db.watchDueCount(),
            builder: (context, snap) {
              final due = snap.data ?? 0;
              if (due == 0) {
                return Row(
                  children: [
                    const Icon(Icons.check_circle_outline,
                        size: 19, color: AppTheme.muted),
                    const SizedBox(width: 7),
                    Text('No cards due right now',
                        style: TextStyle(fontSize: 16, color: AppTheme.muted)),
                  ],
                );
              }
              return InkWell(
                onTap: onStudyTap,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.school_outlined,
                          size: 20, color: AppTheme.coralDark),
                      const SizedBox(width: 7),
                      Text(
                          '$due ${due == 1 ? 'card' : 'cards'} due — study now →',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.coralDark)),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
