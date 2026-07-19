import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_services.dart';
import '../../data/db/database.dart';
import '../../services/ai/prompt_builder.dart';
import '../../services/media/image_import_service.dart';
import '../../services/util/open_url.dart';
import '../../theme.dart';

/// "Assembly line" for adding images fast: for each entry that has no image it
/// shows a one-tap "Copy prompt" (paste into Gemini), then you paste the result
/// back (Ctrl+V or a button) and it saves + jumps to the next entry.
///
/// Nothing is ever deleted here — it only *adds* an image to entries that had
/// none, one at a time.
class ImageStudioScreen extends StatefulWidget {
  final int? catalogueId; // limit to one folder, or null for the whole deck
  const ImageStudioScreen({super.key, this.catalogueId});

  @override
  State<ImageStudioScreen> createState() => _ImageStudioScreenState();
}

class _ImageStudioScreenState extends State<ImageStudioScreen> {
  final ImageImportService _importer = ImageImportService();
  final FocusNode _focus = FocusNode();

  static const int _kBatchSize = 5;

  List<Flashcard> _cards = const [];
  int _index = 0;
  bool _loading = true;
  bool _busy = false;
  Uint8List? _pending; // pasted image awaiting confirmation (single mode)
  String? _error;

  // Batch mode: generate a numbered prompt for several terms at once, then
  // paste the returned images into ordered slots.
  bool _batchMode = true;
  final List<Uint8List?> _slots = []; // one per card in the current batch

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // AppServices.of uses an InheritedWidget, so it can't be read in initState.
    if (!_started) {
      _started = true;
      _load();
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = AppServices.of(context).db;
    final list = await db.cardsWithoutImage(catalogueId: widget.catalogueId);
    if (!mounted) return;
    setState(() {
      _cards = list;
      _index = 0;
      _loading = false;
      _resetSlots();
    });
    _focus.requestFocus();
  }

  Flashcard? get _current =>
      (_index >= 0 && _index < _cards.length) ? _cards[_index] : null;

  /// The visual scene for the prompt: the "Obrazowe:"/"visual:" example line
  /// when present, otherwise the whole example, otherwise the English term.
  String _scene(Flashcard c) {
    final ex = c.exampleSentence ?? '';
    for (final line in ex.split('\n')) {
      final m = RegExp(r'^\s*(obrazowe|visual)\s*:\s*(.+)$',
              caseSensitive: false)
          .firstMatch(line);
      if (m != null) return m.group(2)!.trim();
    }
    return ex.trim().isNotEmpty ? ex.trim() : c.english;
  }

  Future<void> _copyPrompt() async {
    final c = _current;
    if (c == null) return;
    final prompt = PromptBuilder.image(c.english, _scene(c));
    await Clipboard.setData(ClipboardData(text: prompt));
    if (mounted) _toast('Prompt copied — paste it into Gemini');
  }

  Future<void> _copyWord() async {
    final c = _current;
    if (c == null) return;
    await Clipboard.setData(ClipboardData(text: c.english));
    if (mounted) _toast('“${c.english}” copied');
  }

  /// Open Google Images for the current term (faster than AI for some words).
  void _googleImages() {
    final c = _current;
    if (c == null) return;
    openUrl('https://www.google.com/search?tbm=isch&q='
        '${Uri.encodeComponent(c.english)}');
  }

  Future<void> _paste() async {
    final res = await _importer.pasteFromClipboard();
    await _apply(res);
  }

  Future<void> _pickFile() async {
    final res = await _importer.pickFromFile();
    await _apply(res);
  }

  Future<void> _apply(ImageImportResult res) async {
    if (!mounted || res.cancelled) return;
    if (!res.ok) {
      setState(() => _error = res.error);
      return;
    }
    final capped = await _capImage(res.bytes!);
    if (!mounted) return;
    setState(() {
      _pending = capped;
      _error = null;
    });
  }

  Future<void> _saveAndNext() async {
    final c = _current;
    final bytes = _pending;
    if (c == null || bytes == null || _busy) return;
    setState(() => _busy = true);
    final services = AppServices.of(context);
    try {
      await services.db.setImage(c.id, bytes, 'manual');
      // Best-effort upload to Storage so the image reaches other devices.
      if (services.sync.signedIn) {
        try {
          final url = await services.sync.uploadImage(c.id, bytes);
          await services.db.setImageUrl(c.id, url);
        } catch (_) {/* keep local bytes; "Sync images to cloud" can retry */}
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Save failed: $e');
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _pending = null;
      _index++;
    });
    _focus.requestFocus();
  }

  void _skip() {
    setState(() {
      _pending = null;
      _error = null;
      _index++;
    });
    _focus.requestFocus();
  }

  void _prev() {
    if (_index == 0) return;
    setState(() {
      _pending = null;
      _error = null;
      _index--;
    });
    _focus.requestFocus();
  }

  // --- Batch mode -----------------------------------------------------------

  /// The cards in the current batch (up to [_kBatchSize], fewer at the end).
  List<Flashcard> get _batchCards {
    final end = (_index + _kBatchSize).clamp(0, _cards.length);
    return _index < _cards.length ? _cards.sublist(_index, end) : const [];
  }

  /// Resize the slot list to match the current batch, clearing any images.
  void _resetSlots() {
    _slots
      ..clear()
      ..addAll(List<Uint8List?>.filled(_batchCards.length, null));
  }

  /// The scene label used per numbered item: quotes the word so the order is
  /// easy to match, then the visual scene.
  String _sceneLabel(Flashcard c) => '"${c.english}": ${_scene(c)}';

  Future<void> _copyBatchPrompt() async {
    final batch = _batchCards;
    if (batch.isEmpty) return;
    final prompt =
        PromptBuilder.imageBatch([for (final c in batch) _sceneLabel(c)]);
    await Clipboard.setData(ClipboardData(text: prompt));
    if (mounted) {
      _toast('Prompt for ${batch.length} copied — paste it into Gemini');
    }
  }

  Future<void> _pasteIntoSlot(int slot) async {
    final res = await _importer.pasteFromClipboard();
    await _applyToSlot(slot, res);
  }

  Future<void> _pickFileIntoSlot(int slot) async {
    final res = await _importer.pickFromFile();
    await _applyToSlot(slot, res);
  }

  /// Paste into the next empty slot (drives the Ctrl+V shortcut).
  Future<void> _pasteNextEmpty() async {
    final slot = _slots.indexWhere((e) => e == null);
    if (slot == -1) {
      _toast('All ${_slots.length} slots filled — Save & next');
      return;
    }
    await _pasteIntoSlot(slot);
  }

  Future<void> _applyToSlot(int slot, ImageImportResult res) async {
    if (!mounted || res.cancelled) return;
    if (!res.ok) {
      setState(() => _error = res.error);
      return;
    }
    final capped = await _capImage(res.bytes!);
    if (!mounted || slot >= _slots.length) return;
    setState(() {
      _slots[slot] = capped;
      _error = null;
    });
  }

  Future<void> _saveBatch() async {
    if (_busy) return;
    final batch = _batchCards;
    final count = batch.length;
    if (!_slots.any((e) => e != null)) {
      _toast('Paste at least one image first');
      return;
    }
    setState(() => _busy = true);
    final services = AppServices.of(context);
    try {
      for (var i = 0; i < count; i++) {
        final bytes = _slots[i];
        if (bytes == null) continue;
        await services.db.setImage(batch[i].id, bytes, 'manual');
        if (services.sync.signedIn) {
          try {
            final url = await services.sync.uploadImage(batch[i].id, bytes);
            await services.db.setImageUrl(batch[i].id, url);
          } catch (_) {/* keep local bytes; cloud sync can retry */}
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Save failed: $e');
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _index += count; // advance past the whole batch (empty slots are skipped)
      _error = null;
      _resetSlots();
    });
    _focus.requestFocus();
  }

  void _skipBatch() {
    setState(() {
      _index += _batchCards.length;
      _error = null;
      _resetSlots();
    });
    _focus.requestFocus();
  }

  void _toast(String msg) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final total = _cards.length;
    final done = !_loading && _index >= total;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Image Studio'),
        backgroundColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : total == 0
              ? _emptyMessage('Every entry already has an image 🎉')
              : done
                  ? _emptyMessage('All done — no more entries without an image.')
                  : CallbackShortcuts(
                      bindings: {
                        const SingleActivator(LogicalKeyboardKey.keyV,
                            control: true): () {
                          if (_batchMode) {
                            _pasteNextEmpty();
                          } else if (_pending == null) {
                            _paste();
                          }
                        },
                        const SingleActivator(LogicalKeyboardKey.enter): () {
                          if (_batchMode) {
                            _saveBatch();
                          } else if (_pending != null) {
                            _saveAndNext();
                          }
                        },
                      },
                      child: Focus(
                        focusNode: _focus,
                        autofocus: true,
                        child: _body(context, total),
                      ),
                    ),
    );
  }

  Widget _emptyMessage(String msg) => Center(
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
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Back to dictionary'),
              ),
            ],
          ),
        ),
      );

  Widget _body(BuildContext context, int total) {
    final c = _current!;
    final screenW = MediaQuery.of(context).size.width;
    final maxW = screenW < 620 ? screenW : 640.0;
    final batchLen = _batchCards.length;
    final counter = _batchMode
        ? '${_index + 1}–${_index + batchLen} / $total  ·  ${total - _index} left'
        : '${_index + 1} / $total  ·  ${total - _index} left';
    return Column(
      children: [
        LinearProgressIndicator(
          value: total == 0 ? 0 : _index / total,
          minHeight: 6,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(counter,
              style: TextStyle(color: AppTheme.muted, fontSize: 13)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: SegmentedButton<bool>(
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(
                  value: false,
                  label: Text('1 at a time'),
                  icon: Icon(Icons.looks_one_outlined)),
              ButtonSegment(
                  value: true,
                  label: Text('Batch of $_kBatchSize'),
                  icon: Icon(Icons.grid_view_rounded)),
            ],
            selected: {_batchMode},
            onSelectionChanged: (s) => setState(() {
              _batchMode = s.first;
              _pending = null;
              _error = null;
              _resetSlots();
            }),
          ),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                // SelectionArea makes the term, example and prompt drag-
                // selectable and copyable (Ctrl/Cmd+C) — handy for pasting a
                // word into Google Images.
                child: SelectionArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children:
                        _batchMode ? _batchChildren() : _singleChildren(c),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _singleChildren(Flashcard c) => [
        _cardInfo(c),
        const SizedBox(height: 10),
        _quickActions(),
        const SizedBox(height: 14),
        _promptBox(c),
        const SizedBox(height: 14),
        _pasteArea(c),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: const TextStyle(color: Color(0xFFB3261E))),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            TextButton.icon(
              onPressed: _index == 0 ? null : _prev,
              icon: const Icon(Icons.chevron_left),
              label: const Text('Prev'),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _skip,
              icon: const Icon(Icons.skip_next),
              label: const Text('Skip'),
            ),
          ],
        ),
      ];

  List<Widget> _batchChildren() {
    final batch = _batchCards;
    final filled = _slots.where((e) => e != null).length;
    return [
      FilledButton.icon(
        onPressed: _copyBatchPrompt,
        icon: const Icon(Icons.copy_rounded),
        label: Text('Copy prompt for ${batch.length}  →  Gemini'),
      ),
      const SizedBox(height: 6),
      Text(
        'Paste the returned images in order — Ctrl+V fills the next empty slot.',
        style: TextStyle(color: AppTheme.muted, fontSize: 12.5),
      ),
      const SizedBox(height: 14),
      for (var i = 0; i < batch.length; i++) ...[
        _slotCard(i, batch[i]),
        const SizedBox(height: 12),
      ],
      if (_error != null) ...[
        Text(_error!, style: const TextStyle(color: Color(0xFFB3261E))),
        const SizedBox(height: 10),
      ],
      Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: (_busy || filled == 0) ? null : _saveBatch,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_rounded),
              label: Text('Save $filled & next  (Enter)'),
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _busy ? null : _skipBatch,
            icon: const Icon(Icons.skip_next),
            label: const Text('Skip'),
          ),
        ],
      ),
    ];
  }

  /// One numbered slot: the term, and either the pasted image (with a clear
  /// button) or a compact paste/file target that drops into this exact slot.
  Widget _slotCard(int i, Flashcard c) {
    final img = _slots[i];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${i + 1}.  ${c.english}  ·  ${c.polish}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          if (_scene(c).trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('“${_scene(c).trim()}”',
                style: const TextStyle(
                    fontStyle: FontStyle.italic,
                    fontSize: 13,
                    color: Color(0xFF55524B))),
          ],
          const SizedBox(height: 8),
          if (img != null)
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(img,
                      width: 90, height: 90, fit: BoxFit.cover),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Ready',
                      style: TextStyle(
                          color: AppTheme.coralDark,
                          fontWeight: FontWeight.w600)),
                ),
                OutlinedButton(
                  onPressed: () => setState(() => _slots[i] = null),
                  child: const Text('Clear'),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => _pasteIntoSlot(i),
                    icon: const Icon(Icons.content_paste_rounded, size: 18),
                    label: const Text('Paste'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _pickFileIntoSlot(i),
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  label: const Text('File'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cardInfo(Flashcard c) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${c.english}  ·  ${c.polish}',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          if (c.exampleSentence != null &&
              c.exampleSentence!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('“${c.exampleSentence!.trim()}”',
                style: const TextStyle(
                    fontStyle: FontStyle.italic, color: Color(0xFF55524B))),
          ],
        ],
      ),
    );
  }

  Widget _quickActions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _copyWord,
            icon: const Icon(Icons.content_copy_rounded, size: 18),
            label: const Text('Copy word'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _googleImages,
            icon: const Icon(Icons.image_search_rounded, size: 18),
            label: const Text('Google Images'),
          ),
        ),
      ],
    );
  }

  Widget _promptBox(Flashcard c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: _copyPrompt,
          icon: const Icon(Icons.copy_rounded),
          label: const Text('Copy prompt for Gemini'),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.sand,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(PromptBuilder.image(c.english, _scene(c)),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: AppTheme.muted)),
        ),
      ],
    );
  }

  Widget _pasteArea(Flashcard c) {
    if (_pending != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.memory(_pending!, fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _saveAndNext,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_rounded),
                  label: const Text('Save & next  (Enter)'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _busy ? null : () => setState(() => _pending = null),
                child: const Text('Redo'),
              ),
            ],
          ),
        ],
      );
    }
    return DottedPasteZone(onPaste: _paste, onPickFile: _pickFile);
  }

  /// Downscale/cap a pasted image so the deck stays small (mirrors the editor).
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
      final scaledCodec = await ui.instantiateImageCodec(input,
          targetWidth: tw, targetHeight: th);
      final scaled = (await scaledCodec.getNextFrame()).image;
      final data = await scaled.toByteData(format: ui.ImageByteFormat.png);
      scaled.dispose();
      return data?.buffer.asUint8List() ?? input;
    } catch (_) {
      return input;
    }
  }
}

/// The empty target: a big "Paste image" primary action plus a file fallback.
class DottedPasteZone extends StatelessWidget {
  final VoidCallback onPaste;
  final VoidCallback onPickFile;
  const DottedPasteZone(
      {super.key, required this.onPaste, required this.onPickFile});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border, width: 1.4),
      ),
      child: Column(
        children: [
          const Icon(Icons.image_outlined, size: 34, color: AppTheme.muted),
          const SizedBox(height: 8),
          Text('Generate in Gemini, copy the image, then paste it here',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.muted, fontSize: 13)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onPaste,
                  icon: const Icon(Icons.content_paste_rounded),
                  label: const Text('Paste image  (Ctrl+V)'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: onPickFile,
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('File'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
