import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'prompt_builder.dart';

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
