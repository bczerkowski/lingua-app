import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_services.dart';
import '../../data/db/database.dart';
import '../../services/ai/prompt_builder.dart';
import '../../services/media/image_import_service.dart';
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

  List<Flashcard> _cards = const [];
  int _index = 0;
  bool _loading = true;
  bool _busy = false;
  Uint8List? _pending; // pasted image awaiting confirmation
  String? _error;

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
                          if (_pending == null) _paste();
                        },
                        const SingleActivator(LogicalKeyboardKey.enter): () {
                          if (_pending != null) _saveAndNext();
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
    return Column(
      children: [
        LinearProgressIndicator(
          value: total == 0 ? 0 : _index / total,
          minHeight: 6,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text('${_index + 1} / $total  ·  ${total - _index} left',
              style: TextStyle(color: AppTheme.muted, fontSize: 13)),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _cardInfo(c),
                    const SizedBox(height: 14),
                    _promptBox(c),
                    const SizedBox(height: 14),
                    _pasteArea(c),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(_error!,
                          style: const TextStyle(color: Color(0xFFB3261E))),
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
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
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
