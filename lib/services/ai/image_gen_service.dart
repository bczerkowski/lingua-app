import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'prompt_builder.dart';

/// Keys used to store the (optional) Google AI Studio credentials locally.
const String kGoogleKeyPref = 'ai_google_key';
const String kGoogleModelPref = 'ai_google_model';
const String kGoogleDefaultModel = 'gemini-2.5-flash-image';

class ImageGenResult {
  final bool ok;
  final Uint8List? bytes;
  final String? error;
  const ImageGenResult.success(this.bytes)
      : ok = true,
        error = null;
  const ImageGenResult.failure(this.error)
      : ok = false,
        bytes = null;
}

abstract class ImageGenProvider {
  Future<ImageGenResult> generate(String targetWord, String exampleSentence);
}

/// Talks to YOUR backend proxy (which holds the API key — never ship the key in
/// the client). Posts `{ "prompt": ... }` and expects `{ "base64": "..." }`,
/// matching the Gemini/Imagen proxy in `server/gemini_proxy_server.js`.
class ProxyImageGenProvider implements ImageGenProvider {
  final Dio _dio;
  final String endpoint;

  ProxyImageGenProvider(this._dio, {required this.endpoint});

  @override
  Future<ImageGenResult> generate(
      String targetWord, String exampleSentence) async {
    try {
      final prompt = PromptBuilder.image(targetWord, exampleSentence);
      final res = await _dio.post(
        endpoint,
        data: {'prompt': prompt},
        options: Options(
          responseType: ResponseType.json,
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 90),
        ),
      );
      final data = res.data;
      final b64 = data is Map ? data['base64'] : null;
      if (b64 is String && b64.isNotEmpty) {
        return ImageGenResult.success(base64Decode(b64));
      }
      final err = data is Map ? data['error'] : null;
      return ImageGenResult.failure(
          err is String ? err : 'No image returned by the proxy');
    } on DioException catch (e) {
      // Try to surface the proxy's error message if present.
      final body = e.response?.data;
      final msg = body is Map && body['error'] is String
          ? body['error'] as String
          : e.message;
      return ImageGenResult.failure('Network/API error: $msg');
    } catch (e) {
      return ImageGenResult.failure(e.toString());
    }
  }
}

/// Free, keyless image generation via pollinations.ai. Fetches an image for a
/// text prompt directly (CORS-enabled, no API key required). Quality varies —
/// it's a free third-party service — but there's nothing to configure.
class PollinationsImageGenProvider implements ImageGenProvider {
  final Dio _dio;
  PollinationsImageGenProvider(this._dio);

  @override
  Future<ImageGenResult> generate(
      String targetWord, String exampleSentence) async {
    try {
      // Flat-design vector prompt — Flux handles clean illustrations far
      // better than photorealism (that's the Firefly manual path instead).
      final prompt = PromptBuilder.vector(targetWord, exampleSentence);
      // A fresh seed each call so "regenerate" yields a different image.
      final seed = DateTime.now().millisecondsSinceEpoch % 1000000;
      final res = await _dio.get<List<int>>(
        'https://image.pollinations.ai/prompt/${Uri.encodeComponent(prompt)}',
        queryParameters: {
          // Higher-res 16:9 (matches the card's image anchor) for sharper photos.
          'width': 1024,
          'height': 576,
          'nologo': 'true',
          'enhance': 'true',
          // Base flux suits clean flat-design illustrations well.
          'model': 'flux',
          'seed': seed,
        },
        options: Options(
          responseType: ResponseType.bytes,
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 120),
        ),
      );
      final data = res.data;
      if (data != null && data.length > 500) {
        return ImageGenResult.success(Uint8List.fromList(data));
      }
      return const ImageGenResult.failure(
          'The image service returned nothing — try again in a moment.');
    } on DioException catch (e) {
      return ImageGenResult.failure('Network/API error: ${e.message}');
    } catch (e) {
      return ImageGenResult.failure(e.toString());
    }
  }
}

/// Google Gemini image generation via the Generative Language API, using a
/// free Google AI Studio API key stored locally. (Imagen via this API needs a
/// billed project; the Gemini image model works on the free tier.)
class GoogleImageGenProvider implements ImageGenProvider {
  final Dio _dio;
  GoogleImageGenProvider(this._dio);

  @override
  Future<ImageGenResult> generate(
      String targetWord, String exampleSentence) async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString(kGoogleKeyPref)?.trim() ?? '';
    final model = prefs.getString(kGoogleModelPref)?.trim();
    final effModel = (model == null || model.isEmpty) ? kGoogleDefaultModel : model;
    if (key.isEmpty) {
      return const ImageGenResult.failure(
          'No Google API key set — add one in ⋮ → AI image settings.');
    }
    try {
      final prompt = PromptBuilder.image(targetWord, exampleSentence);
      final res = await _dio.post(
        'https://generativelanguage.googleapis.com/v1beta/models/'
        '$effModel:generateContent',
        data: {
          'contents': [
            {
              'parts': [
                {'text': prompt}
              ]
            }
          ],
          'generationConfig': {
            'responseModalities': ['IMAGE']
          },
        },
        options: Options(
          // Key goes in a header, never the URL (keeps it out of any logs).
          headers: {'x-goog-api-key': key, 'Content-Type': 'application/json'},
          responseType: ResponseType.json,
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 120),
        ),
      );
      final b64 = _extractImage(res.data);
      if (b64 != null && b64.isNotEmpty) {
        return ImageGenResult.success(base64Decode(b64));
      }
      return ImageGenResult.failure(
          _extractBlock(res.data) ?? 'Gemini returned no image — try again.');
    } on DioException catch (e) {
      final body = e.response?.data;
      final msg = body is Map && body['error'] is Map
          ? (body['error']['message'] ?? e.message).toString()
          : (e.message ?? 'Network error');
      return ImageGenResult.failure('Gemini error: $msg');
    } catch (e) {
      return ImageGenResult.failure(e.toString());
    }
  }

  String? _extractImage(dynamic data) {
    if (data is! Map) return null;
    final candidates = data['candidates'];
    if (candidates is! List || candidates.isEmpty) return null;
    final content = (candidates.first as Map)['content'];
    if (content is! Map) return null;
    final parts = content['parts'];
    if (parts is! List) return null;
    for (final p in parts) {
      if (p is Map) {
        final inline = p['inlineData'] ?? p['inline_data'];
        if (inline is Map && inline['data'] is String) {
          return inline['data'] as String;
        }
      }
    }
    return null;
  }

  String? _extractBlock(dynamic data) {
    if (data is! Map) return null;
    final pf = data['promptFeedback'];
    if (pf is Map && pf['blockReason'] != null) {
      return 'Blocked by the safety filter (${pf['blockReason']}).';
    }
    return null;
  }
}

/// Default generator: uses Google Gemini when an API key has been saved,
/// otherwise the free keyless pollinations.ai. Re-reads the key each call so
/// setting/clearing it takes effect without restarting the app.
class DefaultImageGenProvider implements ImageGenProvider {
  final ImageGenProvider google;
  final ImageGenProvider pollinations;
  DefaultImageGenProvider({required this.google, required this.pollinations});

  @override
  Future<ImageGenResult> generate(
      String targetWord, String exampleSentence) async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString(kGoogleKeyPref)?.trim() ?? '';
    if (key.isEmpty) {
      return pollinations.generate(targetWord, exampleSentence);
    }
    // Try Gemini first; if it fails (e.g. the image model needs billing, or a
    // rate limit), fall back to the free generator so the user still gets an
    // image instead of a hard error.
    final g = await google.generate(targetWord, exampleSentence);
    if (g.ok) return g;
    final p = await pollinations.generate(targetWord, exampleSentence);
    return p.ok ? p : g;
  }
}

/// Demo provider used when no backend is configured: it always "fails" so you
/// can exercise the manual-image fallback flow end to end without an API key.
class DisabledImageGenProvider implements ImageGenProvider {
  @override
  Future<ImageGenResult> generate(String targetWord, String exampleSentence) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return const ImageGenResult.failure(
        'No image backend configured (demo mode). Add your own image instead.');
  }
}
