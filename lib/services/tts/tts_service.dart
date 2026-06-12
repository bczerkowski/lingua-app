import 'package:flutter_tts/flutter_tts.dart';

/// Native, offline-capable text-to-speech for both Polish and English.
class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;

  Future<void> _ensureInit() async {
    if (_ready) return;
    await _tts.setVolume(1.0);
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
    _ready = true;
  }

  /// [lang] is a BCP-47 tag: 'pl-PL' for Polish, 'en-US' for English.
  Future<void> speak(String text, String lang) async {
    if (text.trim().isEmpty) return;
    await _ensureInit();
    await _tts.stop();
    await _tts.setLanguage(lang);
    await _tts.speak(text);
  }

  Future<void> stop() => _tts.stop();
}
