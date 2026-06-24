import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../data/db/database.dart';
import '../../services/media/image_import_service.dart';

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
  final _tags = TextEditingController();

  int? _catalogueId;
  bool _isCard = true;
  Uint8List? _imageBytes;
  String? _imageSource;
  String? _imageError;
  bool _generating = false;
  bool _loaded = false;
  final ImageImportService _importer = ImageImportService();

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
    setState(() {
      _polish.text = c.polish;
      _english.text = c.english;
      _example.text = c.exampleSentence ?? '';
      _definition.text = c.englishDefinition ?? '';
      _tags.text = c.tags;
      _catalogueId = c.catalogueId;
      _isCard = c.isCard;
      _imageBytes = c.imageBytes;
      _imageSource = c.imageSource;
    });
  }

  @override
  void dispose() {
    for (final c in [_polish, _english, _example, _definition, _tags]) {
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
            _field(_polish, 'Polish term', required: true),
            _field(_english, 'English term', required: true),
            _field(_example, 'Example sentence', maxLines: 2),
            _field(_definition, 'English definition', maxLines: 2),
            _field(_tags, 'Tags — first is part of speech (e.g. noun;animals)'),
            const SizedBox(height: 8),
            _CatalogueDropdown(
              db: db,
              value: _catalogueId,
              onChanged: (v) => setState(() => _catalogueId = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Include in study deck'),
              value: _isCard,
              onChanged: (v) => setState(() => _isCard = v),
            ),
            const SizedBox(height: 8),
            _imageSection(),
            const SizedBox(height: 20),
            FilledButton.icon(
              icon: const Icon(Icons.save),
              label: Text(_isNew ? 'Create' : 'Save changes'),
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label,
      {bool required = false, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        maxLines: maxLines,
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
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                clipBehavior: Clip.antiAlias,
                child: _generating
                    ? const Center(child: CircularProgressIndicator())
                    : _imageBytes != null
                        ? Image.memory(_imageBytes!, fit: BoxFit.cover)
                        : const Center(
                            child: Text('No image',
                                style: TextStyle(color: Colors.grey))),
              ),
            ),
            if (_imageError != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
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
            const SizedBox(height: 10),
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
                if (_imageBytes != null)
                  TextButton.icon(
                    icon: const Icon(Icons.clear, size: 18),
                    label: const Text('Remove'),
                    onPressed: () => setState(() {
                      _imageBytes = null;
                      _imageSource = null;
                    }),
                  ),
              ],
            ),
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
    setState(() {
      _generating = false;
      if (result.ok && result.bytes != null) {
        _imageBytes = result.bytes;
        _imageSource = 'ai';
      } else {
        // Failure -> surface the error so the manual-upload path is obvious.
        _imageError = result.error;
      }
    });
  }

  /// Pick a PNG / JPG / PDF from disk (PDFs are rasterized to an image).
  Future<void> _pickFile() async {
    final result = await _importer.pickFromFile();
    _applyImport(result);
  }

  /// Paste an image straight from the clipboard (e.g. a Print-Screen capture).
  Future<void> _pasteScreenshot() async {
    final result = await _importer.pasteFromClipboard();
    _applyImport(result);
  }

  void _applyImport(ImageImportResult result) {
    if (!mounted || result.cancelled) return;
    setState(() {
      if (result.ok) {
        _imageBytes = result.bytes;
        _imageSource = 'manual';
        _imageError = null;
      } else {
        _imageError = result.error;
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------
  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final db = AppServices.of(context).db;
    final now = DateTime.now();

    if (_isNew) {
      await db.into(db.cards).insert(CardsCompanion.insert(
            polish: _polish.text.trim(),
            english: _english.text.trim(),
            exampleSentence: Value(_nullIfEmpty(_example.text)),
            englishDefinition: Value(_nullIfEmpty(_definition.text)),
            tags: Value(_tags.text.trim()),
            catalogueId: Value(_catalogueId),
            imageBytes: Value(_imageBytes),
            imageSource: Value(_imageSource),
            isCard: Value(_isCard),
            dueDate: Value(_isCard ? now : null),
          ));
    } else {
      await (db.update(db.cards)..where((t) => t.id.equals(widget.cardId!)))
          .write(CardsCompanion(
        polish: Value(_polish.text.trim()),
        english: Value(_english.text.trim()),
        exampleSentence: Value(_nullIfEmpty(_example.text)),
        englishDefinition: Value(_nullIfEmpty(_definition.text)),
        tags: Value(_tags.text.trim()),
        catalogueId: Value(_catalogueId),
        imageBytes: Value(_imageBytes),
        imageSource: Value(_imageSource),
        isCard: Value(_isCard),
        updatedAt: Value(now),
      ));
    }
    if (mounted) Navigator.of(context).pop(true);
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
