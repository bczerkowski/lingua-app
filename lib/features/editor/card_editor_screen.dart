import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../data/db/database.dart';
import '../../services/assist/word_assist_service.dart';
import '../../services/media/image_import_service.dart';
import '../../theme.dart';

/// Create or edit a card. Supports editing every field, choosing a catalogue,
/// deleting, AI image generation (with the manual-upload fallback if it fails).
class CardEditorScreen extends StatefulWidget {
  final int? cardId; // null = create new
  const CardEditorScreen({super.key, this.cardId});

  @override
  State<CardEditorScreen> createState() => _CardEditorScreenState();
}

class _CardEditorScreenState extends State<CardEditorScreen> {
  final _form = GlobalKey<FormState>();
  final _polish = TextEditingController();
  final _english = TextEditingController();
  final _example = TextEditingController();
  final _definition = TextEditingController();
  final _note = TextEditingController();
  List<String> _tagList = [];

  int? _catalogueId;
  bool _isCard = true;
  Uint8List? _imageBytes;
  String? _imageSource;
  String? _imageError;
  bool _generating = false;
  bool _saving = false;
  bool _loaded = false;
  final ImageImportService _importer = ImageImportService();
  final WordAssistService _assist = WordAssistService();
  String? _busyAction; // which assist button is currently running

  // Additional Polish translations for the same term (the example/definition
  // stay shared). Each is its own removable field.
  final List<TextEditingController> _extraPolish = [];

  bool get _isNew => widget.cardId == null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      if (!_isNew) _loadCard();
    }
  }

  Future<void> _loadCard() async {
    final db = AppServices.of(context).db;
    final c = await db.getCard(widget.cardId!);
    if (c == null || !mounted) return;
    // Populate the primary fields first — this must never depend on the
    // (newer) meanings query succeeding.
    setState(() {
      _polish.text = c.polish;
      _english.text = c.english;
      _example.text = c.exampleSentence ?? '';
      _definition.text = c.englishDefinition ?? '';
      _note.text = c.note ?? '';
      _tagList = c.tags
          .split(';')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();
      _catalogueId = c.catalogueId;
      _isCard = c.isCard;
      _imageBytes = c.imageBytes;
      _imageSource = c.imageSource;
    });
    // Additional Polish translations are best-effort; a failure here must not
    // blank the card.
    try {
      final extra = await db.meaningsFor(widget.cardId!);
      if (!mounted) return;
      setState(() {
        for (final m in extra) {
          if (m.polishTranslation.trim().isNotEmpty) {
            _extraPolish.add(TextEditingController(text: m.polishTranslation));
          }
        }
      });
    } catch (_) {/* ignore — primary fields already loaded */}
  }

  @override
  void dispose() {
    for (final c in [_polish, _english, _example, _definition, _note]) {
      c.dispose();
    }
    for (final c in _extraPolish) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = AppServices.of(context).db;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'New entry' : 'Edit card'),
        actions: [
          if (!_isNew)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _field(_english, 'English term', required: true, maxLength: 200),
            _field(_polish, 'Polish term', required: true, maxLength: 200),
            // Additional Polish translations for the same word (e.g. a verb and
            // an adjective sense). Example/definition below stay shared.
            for (var i = 0; i < _extraPolish.length; i++) _extraPolishField(i),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Polish meaning'),
                onPressed: () =>
                    setState(() => _extraPolish.add(TextEditingController())),
              ),
            ),
            _assistRow('Suggest Polish meaning', Icons.translate, 'pl',
                _suggestPolish),
            _field(_example, 'Example sentence', maxLines: 2, maxLength: 300),
            _assistRow('Generate example sentence', Icons.auto_awesome, 'ex',
                _genExample),
            _field(_definition, 'English definition', maxLines: 2, maxLength: 500),
            _assistRow('Generate definition', Icons.auto_awesome, 'def',
                _genDefinition),
            const SizedBox(height: 12),
            _TagInput(
              // Re-seed the chip editor once the card's tags have loaded.
              key: ValueKey('tags_${_tagList.join('|')}'),
              initial: _tagList,
              onChanged: (t) => _tagList = t,
            ),
            _assistRow('Suggest tags', Icons.sell_outlined, 'tags',
                _suggestTags),
            const SizedBox(height: 12),
            _CatalogueDropdown(
              db: db,
              value: _catalogueId,
              onChanged: (v) => setState(() => _catalogueId = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Study this card'),
              value: _isCard,
              onChanged: (v) => setState(() => _isCard = v),
            ),
            const SizedBox(height: 8),
            _imageSection(),
            const SizedBox(height: 16),
            // Personal note — kept last; shown subtly on the study card.
            _field(_note, 'Note (optional — tips, mnemonics)',
                maxLines: 3, maxLength: 500),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save),
              label: Text(_saving
                  ? 'Saving…'
                  : (_isNew ? 'Create' : 'Save changes')),
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label,
      {bool required = false, int maxLines = 1, int? maxLength}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        maxLines: maxLines,
        maxLength: maxLength,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
            : null,
      ),
    );
  }

  /// Cap an imported/generated image so the stored BLOB stays small. Large
  /// photos or AI images (multi-MB) bloat the offline DB and can make the
  /// insert fail; downscale anything bigger than [maxDim]px on its long edge.
  /// Best-effort: returns the original bytes if decoding/encoding fails.
  Future<Uint8List> _capImage(Uint8List input,
      {int maxDim = 1024, int maxBytes = 700 * 1024}) async {
    try {
      final codec = await ui.instantiateImageCodec(input);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final longest = img.width > img.height ? img.width : img.height;
      if (longest <= maxDim && input.lengthInBytes <= maxBytes) {
        img.dispose();
        return input;
      }
      final scale = maxDim / longest;
      final tw = (img.width * scale).round().clamp(1, maxDim);
      final th = (img.height * scale).round().clamp(1, maxDim);
      img.dispose();
      final scaledCodec =
          await ui.instantiateImageCodec(input, targetWidth: tw, targetHeight: th);
      final scaled = (await scaledCodec.getNextFrame()).image;
      final data = await scaled.toByteData(format: ui.ImageByteFormat.png);
      scaled.dispose();
      return data?.buffer.asUint8List() ?? input;
    } catch (_) {
      return input;
    }
  }

  Widget _extraPolishField(int i) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _extraPolish[i],
              decoration: InputDecoration(
                labelText: 'Polish meaning ${i + 2}',
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            tooltip: 'Remove',
            onPressed: () => setState(() => _extraPolish.removeAt(i).dispose()),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Small, optional "assist" helpers (free dictionary/translation APIs)
  // ---------------------------------------------------------------------------
  Widget _assistRow(
      String label, IconData icon, String key, Future<void> Function() run) {
    final busy = _busyAction == key;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          icon: busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(icon, size: 16),
          label: Text(label, style: const TextStyle(fontSize: 12.5)),
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.coralDark,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          ),
          onPressed: _busyAction != null ? null : () => _runAssist(key, run),
        ),
      ),
    );
  }

  Future<void> _runAssist(String key, Future<void> Function() run) async {
    setState(() => _busyAction = key);
    try {
      await run();
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  bool _needEnglish() {
    if (_english.text.trim().isEmpty) {
      _toast('Enter the English term first');
      return false;
    }
    return true;
  }

  Future<void> _suggestPolish() async {
    if (!_needEnglish()) return;
    final pl = await _assist.translateToPolish(_english.text.trim());
    if (!mounted) return;
    if (pl != null) {
      _polish.text = pl;
    } else {
      _toast('Could not fetch a translation');
    }
  }

  Future<void> _genExample() async {
    if (!_needEnglish()) return;
    final d = await _assist.lookup(_english.text.trim());
    if (!mounted) return;
    if (d?.example != null) {
      _example.text = d!.example!;
    } else {
      _toast('No example found for “${_english.text.trim()}”');
    }
  }

  Future<void> _genDefinition() async {
    if (!_needEnglish()) return;
    final d = await _assist.lookup(_english.text.trim());
    if (!mounted) return;
    if (d?.definition != null) {
      _definition.text = d!.definition!;
    } else {
      _toast('No definition found for “${_english.text.trim()}”');
    }
  }

  static const _suggestedTags = [
    'academic',
    'travel',
    'business',
    'aviation',
    'daily English',
    'difficult',
    'phrasal verb',
    'false friend',
    'Academic English',
    'Aviation English',
    'Customer English',
    'Business English',
  ];

  Future<void> _suggestTags() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Suggested tags',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text('Tap to add or remove.',
                  style: TextStyle(color: AppTheme.muted, fontSize: 13)),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in _suggestedTags)
                    FilterChip(
                      label: Text(t),
                      selected: _tagList.contains(t),
                      showCheckmark: true,
                      onSelected: (sel) => setSheet(() {
                        if (sel) {
                          if (!_tagList.contains(t)) _tagList.add(t);
                        } else {
                          _tagList.remove(t);
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted) setState(() {}); // rebuild the chip editor with new tags
  }

  // ---------------------------------------------------------------------------
  // Visual anchor: AI generation + manual fallback
  // ---------------------------------------------------------------------------
  Widget _imageSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Visual anchor',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            if (_generating)
              const SizedBox(
                height: 60,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_imageBytes != null)
              // Compact preview + change/remove (no longer fills the screen).
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(_imageBytes!,
                        width: 132, height: 88, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.image_outlined, size: 18),
                          label: const Text('Change image'),
                          onPressed: _pickFile,
                        ),
                        const SizedBox(height: 6),
                        TextButton.icon(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('Remove image'),
                          style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFB3261E)),
                          onPressed: () => setState(() {
                            _imageBytes = null;
                            _imageSource = null;
                          }),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            else ...[
              if (_imageError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber,
                            color: Colors.orange, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('Generation failed: $_imageError',
                              style: const TextStyle(fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: const Text('Generate with AI'),
                    onPressed: _generating ? null : _generateImage,
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.upload_file, size: 18),
                    label: const Text('PNG / JPG / PDF'),
                    onPressed: _pickFile,
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.content_paste, size: 18),
                    label: const Text('Paste screenshot'),
                    onPressed: _pasteScreenshot,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _generateImage() async {
    final word = _english.text.trim();
    if (word.isEmpty) {
      _toast('Enter the English term first');
      return;
    }
    setState(() {
      _generating = true;
      _imageError = null;
    });
    final provider = AppServices.of(context).imageGen;
    final result = await provider.generate(word, _example.text.trim());
    if (!mounted) return;
    if (result.ok && result.bytes != null) {
      final capped = await _capImage(result.bytes!);
      if (!mounted) return;
      setState(() {
        _generating = false;
        _imageBytes = capped;
        _imageSource = 'ai';
      });
    } else {
      // Failure -> surface the error so the manual-upload path is obvious.
      setState(() {
        _generating = false;
        _imageError = result.error;
      });
    }
  }

  /// Pick a PNG / JPG / PDF from disk (PDFs are rasterized to an image).
  Future<void> _pickFile() async {
    final result = await _importer.pickFromFile();
    await _applyImport(result);
  }

  /// Paste an image straight from the clipboard (e.g. a Print-Screen capture).
  Future<void> _pasteScreenshot() async {
    final result = await _importer.pasteFromClipboard();
    await _applyImport(result);
  }

  Future<void> _applyImport(ImageImportResult result) async {
    if (!mounted || result.cancelled) return;
    if (result.ok) {
      final capped = await _capImage(result.bytes!);
      if (!mounted) return;
      setState(() {
        _imageBytes = capped;
        _imageSource = 'manual';
        _imageError = null;
      });
    } else {
      setState(() => _imageError = result.error);
    }
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------
  Future<void> _save() async {
    if (_saving) return;
    // Validation failures used to fail silently if the empty field was scrolled
    // off-screen — surface a message as well.
    if (!_form.currentState!.validate()) {
      _toast('Add the English and Polish terms first');
      return;
    }
    setState(() => _saving = true);
    final db = AppServices.of(context).db;
    final now = DateTime.now();
    try {
      int cardId;
      if (_isNew) {
        cardId = await db.into(db.cards).insert(CardsCompanion.insert(
              polish: _polish.text.trim(),
              english: _english.text.trim(),
              exampleSentence: Value(_nullIfEmpty(_example.text)),
              englishDefinition: Value(_nullIfEmpty(_definition.text)),
              note: Value(_nullIfEmpty(_note.text)),
              tags: Value(_tagList.join(';')),
              catalogueId: Value(_catalogueId),
              imageBytes: Value(_imageBytes),
              imageSource: Value(_imageSource),
              isCard: Value(_isCard),
              dueDate: Value(_isCard ? now : null),
            ));
      } else {
        cardId = widget.cardId!;
        await (db.update(db.cards)..where((t) => t.id.equals(cardId)))
            .write(CardsCompanion(
          polish: Value(_polish.text.trim()),
          english: Value(_english.text.trim()),
          exampleSentence: Value(_nullIfEmpty(_example.text)),
          englishDefinition: Value(_nullIfEmpty(_definition.text)),
          note: Value(_nullIfEmpty(_note.text)),
          tags: Value(_tagList.join(';')),
          catalogueId: Value(_catalogueId),
          imageBytes: Value(_imageBytes),
          imageSource: Value(_imageSource),
          isCard: Value(_isCard),
          updatedAt: Value(now),
        ));
      }
      // Persist the additional Polish translations.
      await db.replaceMeanings(
        cardId,
        [
          for (final c in _extraPolish)
            (polish: c.text, definition: null, example: null),
        ],
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      // Never fail silently: tell the user why the save didn't go through.
      if (mounted) {
        setState(() => _saving = false);
        _toast('Couldn\'t save: $e');
      }
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete card?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await AppServices.of(context).db.deleteCard(widget.cardId!);
    if (mounted) Navigator.of(context).pop(true);
  }

  String? _nullIfEmpty(String s) => s.trim().isEmpty ? null : s.trim();

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

class _CatalogueDropdown extends StatelessWidget {
  final AppDatabase db;
  final int? value;
  final ValueChanged<int?> onChanged;
  const _CatalogueDropdown(
      {required this.db, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Catalogue>>(
      stream: db.watchCatalogues(),
      builder: (context, snap) {
        final cats = snap.data ?? const [];
        return Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int?>(
                initialValue: value,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Catalogue',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<int?>(
                      value: null, child: Text('— none —')),
                  for (final c in cats)
                    DropdownMenuItem<int?>(value: c.id, child: Text(c.name)),
                ],
                onChanged: onChanged,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.create_new_folder_outlined),
              tooltip: 'New catalogue',
              onPressed: () => _newCatalogue(context),
            ),
          ],
        );
      },
    );
  }

  Future<void> _newCatalogue(BuildContext context) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New catalogue'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. Medical'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Create')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final id = await db.createCatalogue(name);
    onChanged(id);
  }
}

/// Chip-style tag editor: type a word then press space/comma/Enter to turn it
/// into a chip. The first chip is the part of speech.
class _TagInput extends StatefulWidget {
  final List<String> initial;
  final ValueChanged<List<String>> onChanged;
  const _TagInput(
      {super.key, required this.initial, required this.onChanged});

  @override
  State<_TagInput> createState() => _TagInputState();
}

class _TagInputState extends State<_TagInput> {
  late final List<String> _tags = [...widget.initial];
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit(String raw) {
    final parts = raw
        .split(RegExp(r'[;,\s]+'))
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty);
    var changed = false;
    for (final p in parts) {
      if (!_tags.contains(p)) {
        _tags.add(p);
        changed = true;
      }
    }
    _ctrl.clear();
    setState(() {});
    if (changed) widget.onChanged(_tags);
    _focus.requestFocus();
  }

  void _onChanged(String v) {
    if (v.endsWith(' ') || v.endsWith(',') || v.endsWith(';')) _commit(v);
  }

  void _remove(String t) {
    setState(() => _tags.remove(t));
    widget.onChanged(_tags);
  }

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Tags',
        helperText: 'Type a word, then space or comma. First tag = part of speech.',
        border: OutlineInputBorder(),
        floatingLabelBehavior: FloatingLabelBehavior.always,
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (var i = 0; i < _tags.length; i++)
            Chip(
              label: Text(i == 0 ? _tags[i].toUpperCase() : '#${_tags[i]}'),
              labelStyle: TextStyle(
                  fontSize: 12.5,
                  fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w500,
                  color: i == 0 ? const Color(0xFF55524B) : AppTheme.muted),
              backgroundColor: i == 0 ? AppTheme.sand : Colors.white,
              side: i == 0
                  ? BorderSide.none
                  : const BorderSide(color: AppTheme.border),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onDeleted: () => _remove(_tags[i]),
            ),
          IntrinsicWidth(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 90),
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                decoration: const InputDecoration.collapsed(hintText: 'add tag…'),
                onChanged: _onChanged,
                onSubmitted: _commit,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
