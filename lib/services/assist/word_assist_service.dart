import 'package:dio/dio.dart';

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
}
