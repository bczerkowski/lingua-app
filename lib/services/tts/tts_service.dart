import 'package:flutter_tts/flutter_tts.dart';

/// Text-to-speech for Polish and English.
///
/// On the web the rate maps 1:1 to the browser's SpeechSynthesis (1.0 = normal;
/// the old 0.45 was half-speed, which sounded like slow syllable-by-syllable
/// reading). We also actively pick the most natural available voice per
/// language instead of leaving the browser on its default (often the robotic
/// "Microsoft Zira").
class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;
  Map<String, String>? _enVoice;
  Map<String, String>? _plVoice;

  Future<void> _ensureInit() async {
    if (_ready) return;
    await _tts.setVolume(1.0);
    await _tts.setSpeechRate(0.9); // slightly slower than normal, still natural
    await _tts.setPitch(1.0);
    _ready = true;
  }

  /// [lang] is a BCP-47 tag: 'pl-PL' for Polish, 'en-US' for English.
  Future<void> speak(String text, String lang) async {
    if (text.trim().isEmpty) return;
    await _ensureInit();
    await _tts.stop();
    await _tts.setLanguage(lang);
    final voice = await _voiceFor(lang);
    if (voice != null) {
      try {
        await _tts.setVoice(voice);
      } catch (_) {/* keep the language default if this voice is unavailable */}
    }
    await _tts.speak(text);
  }

  Future<void> stop() => _tts.stop();

  /// Best voice for the language, chosen once and cached. Browser voices load
  /// asynchronously, so we (re)query until they're available.
  Future<Map<String, String>?> _voiceFor(String lang) async {
    final isPl = lang.toLowerCase().startsWith('pl');
    if ((isPl ? _plVoice : _enVoice) == null) {
      await _pickVoices();
    }
    return isPl ? _plVoice : _enVoice;
  }

  Future<void> _pickVoices() async {
    try {
      final raw = await _tts.getVoices;
      if (raw is! List) return;
      final voices = raw
          .whereType<Map>()
          .map((v) => v.map((k, val) => MapEntry('$k', '$val')))
          .toList();
      _enVoice ??= _best(voices, 'en');
      _plVoice ??= _best(voices, 'pl');
    } catch (_) {/* fall back to the browser's default voice */}
  }

  /// Pick the most natural-sounding voice whose locale starts with [langPrefix].
  /// Modern neural/"natural"/Google voices score highest; robotic ones (e.g.
  /// Microsoft Zira/David) fall to the bottom.
  Map<String, String>? _best(List<Map<String, String>> voices, String langPrefix) {
    final matching = voices
        .where((v) => (v['locale'] ?? '').toLowerCase().startsWith(langPrefix))
        .toList();
    if (matching.isEmpty) return null;

    // Higher index = preferred.
    const ranked = [
      'zira', 'david', 'mark', 'hazel', // known robotic Microsoft voices (low)
      'microsoft',
      'google',
      'online', 'natural', 'neural',
    ];
    int score(Map<String, String> v) {
      final n = (v['name'] ?? '').toLowerCase();
      var best = -1;
      for (var i = 0; i < ranked.length; i++) {
        if (n.contains(ranked[i])) best = i;
      }
      return best;
    }

    matching.sort((a, b) => score(b).compareTo(score(a)));
    // Prefer en-US among equally good English voices.
    if (langPrefix == 'en') {
      final topScore = score(matching.first);
      final us = matching.firstWhere(
        (v) =>
            (v['locale'] ?? '').toLowerCase() == 'en-us' &&
            score(v) == topScore,
        orElse: () => matching.first,
      );
      return us;
    }
    return matching.first;
  }
}
