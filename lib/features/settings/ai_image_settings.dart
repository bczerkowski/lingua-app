import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/ai/image_gen_service.dart';
import '../../theme.dart';

/// Lets the user paste a free Google AI Studio API key so image generation uses
/// Gemini. Empty key = the free keyless pollinations.ai generator.
Future<void> showAiImageSettings(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _AiImageSettingsDialog(prefs: prefs),
  );
}

class _AiImageSettingsDialog extends StatefulWidget {
  final SharedPreferences prefs;
  const _AiImageSettingsDialog({required this.prefs});

  @override
  State<_AiImageSettingsDialog> createState() => _AiImageSettingsDialogState();
}

class _AiImageSettingsDialogState extends State<_AiImageSettingsDialog> {
  late final TextEditingController _key =
      TextEditingController(text: widget.prefs.getString(kGoogleKeyPref) ?? '');
  late final TextEditingController _model = TextEditingController(
      text: widget.prefs.getString(kGoogleModelPref) ?? kGoogleDefaultModel);
  bool _obscure = true;

  @override
  void dispose() {
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final k = _key.text.trim();
    final m = _model.text.trim().isEmpty ? kGoogleDefaultModel : _model.text.trim();
    if (k.isEmpty) {
      await widget.prefs.remove(kGoogleKeyPref);
    } else {
      await widget.prefs.setString(kGoogleKeyPref, k);
    }
    await widget.prefs.setString(kGoogleModelPref, m);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(k.isEmpty
              ? 'Using the free Pollinations generator.'
              : 'Saved — image generation now uses Gemini.')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('AI image generation'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paste a free Google AI Studio API key to generate images with '
              'Gemini (better quality). Leave it empty to use the free '
              'keyless Pollinations generator.',
              style: TextStyle(fontSize: 13, color: AppTheme.muted, height: 1.35),
            ),
            const SizedBox(height: 8),
            const SelectableText(
              'Get a free key at: aistudio.google.com/apikey',
              style: TextStyle(fontSize: 12.5, color: AppTheme.muted),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _key,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Google AI Studio API key',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show' : 'Hide',
                  icon: Icon(
                      _obscure ? Icons.visibility : Icons.visibility_off,
                      size: 20),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _model,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Model',
                border: OutlineInputBorder(),
                helperText: 'Default: gemini-2.5-flash-image',
                helperMaxLines: 2,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
