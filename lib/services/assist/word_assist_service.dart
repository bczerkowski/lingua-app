import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ai/image_gen_service.dart' show kGoogleKeyPref;

/// Result of a dictionary lookup (dictionaryapi.dev).
class DictLookup {
  final String? definition;
  final String? example;
  final List<String> partsOfSpeech;
  final List<String> synonyms;
  const DictLookup({
    this.definition,
    this.example,
    this.partsOfSpeech = const [],
    this.synonyms = const [],
  });
}

/// Free, keyless helpers for filling card fields from public web APIs:
/// MyMemory for EN→PL translation and dictionaryapi.dev for English
/// definitions, examples, and part of speech. All are CORS-enabled, so they
/// work directly from the browser with no backend.
class WordAssistService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 12),
  ));

  /// English → Polish via MyMemory. Returns null on failure.
  Future<String?> translateToPolish(String english) async {
    try {
      final r = await _dio.get(
        'https://api.mymemory.translated.net/get',
        queryParameters: {'q': english, 'langpair': 'en|pl'},
      );
      final t = r.data?['responseData']?['translatedText'];
      if (t is String && t.trim().isNotEmpty) return t.trim();
    } catch (_) {}
    return null;
  }

  /// Look up an English word's definition/example/part of speech/synonyms.
  /// Returns null if not found.
  Future<DictLookup?> lookup(String english) async {
    try {
      final r = await _dio.get(
        'https://api.dictionaryapi.dev/api/v2/entries/en/'
        '${Uri.encodeComponent(english.trim())}',
      );
      final data = r.data;
      if (data is! List || data.isEmpty) return null;

      String? def, ex;
      final pos = <String>{};
      final syn = <String>{};
      for (final entry in data) {
        for (final m in (entry['meanings'] as List? ?? const [])) {
          final p = m['partOfSpeech'];
          if (p is String && p.isNotEmpty) pos.add(p);
          for (final s in (m['synonyms'] as List? ?? const [])) {
            if (s is String) syn.add(s);
          }
          for (final d in (m['definitions'] as List? ?? const [])) {
            def ??= d['definition'] as String?;
            ex ??= d['example'] as String?;
          }
        }
      }
      return DictLookup(
        definition: def,
        example: ex,
        partsOfSpeech: pos.toList(),
        synonyms: syn.toList(),
      );
    } catch (_) {
      return null;
    }
  }

  /// True when a Google AI Studio key is saved (so the AI helpers can run).
  Future<bool> hasAiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(kGoogleKeyPref)?.trim() ?? '').isNotEmpty;
  }

  /// A livelier, smarter example sentence via Gemini — understands phrasal
  /// verbs, idioms and expressions, unlike the single-word dictionary.
  Future<String?> aiExample(String english) => _gemini(
        "You are helping build a language-learning flashcard. The English term "
        "is \"$english\" — it may be a single word, a phrasal verb, an idiom, "
        "or an expression (sometimes with a placeholder like 'something' or "
        "'someone'). Write ONE natural, vivid example sentence that uses the "
        "term correctly and idiomatically, replacing any placeholder with a "
        "real word. 8 to 16 words, modern everyday context, easy for a learner. "
        "Return ONLY the sentence: no quotes, no label, no explanation.",
      );

  /// A clear learner-friendly definition via Gemini — also handles phrasal
  /// verbs, idioms and expressions the dictionary can't.
  Future<String?> aiDefinition(String english) => _gemini(
        "Define the English term \"$english\" for a language learner. It may be "
        "a single word, a phrasal verb, an idiom, or an expression. Explain "
        "clearly what it means and how it is used, in 1 to 2 short sentences of "
        "plain English. Return ONLY the definition text: no quotes, no label, "
        "do not repeat the term as a heading.",
      );

  /// Calls Gemini text (free on the AI Studio free tier). Returns null when no
  /// key is saved or on any error, so callers can fall back to the dictionary.
  Future<String?> _gemini(String prompt) async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString(kGoogleKeyPref)?.trim() ?? '';
    if (key.isEmpty) return null;
    try {
      final r = await _dio.post(
        'https://generativelanguage.googleapis.com/v1beta/models/'
        'gemini-2.5-flash:generateContent',
        data: {
          'contents': [
            {
              'parts': [
                {'text': prompt}
              ]
            }
          ],
        },
        options: Options(
          headers: {'x-goog-api-key': key, 'Content-Type': 'application/json'},
        ),
      );
      var text = _firstText(r.data)?.trim();
      if (text == null || text.isEmpty) return null;
      // Strip wrapping quotes the model sometimes adds.
      text = text.replaceAll(RegExp(r'^["“”]+|["“”]+$'), '').trim();
      return text.isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  String? _firstText(dynamic data) {
    if (data is! Map) return null;
    final cands = data['candidates'];
    if (cands is! List || cands.isEmpty) return null;
    final content = (cands.first as Map)['content'];
    final parts = content is Map ? content['parts'] : null;
    if (parts is! List) return null;
    for (final p in parts) {
      if (p is Map && p['text'] is String) return p['text'] as String;
    }
    return null;
  }
}
