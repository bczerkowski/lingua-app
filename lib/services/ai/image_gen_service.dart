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

/// Talks to YOUR backend proxy (which holds the OpenAI key — never ship the key
/// in the client). The proxy is expected to return raw PNG bytes.
///
/// See `server/imageRoute.js` in the project README for the matching endpoint.
class ProxyImageGenProvider implements ImageGenProvider {
  final Dio _dio;
  final String endpoint;

  ProxyImageGenProvider(this._dio, {required this.endpoint});

  @override
  Future<ImageGenResult> generate(String targetWord, String exampleSentence) async {
    try {
      final prompt = PromptBuilder.image(targetWord, exampleSentence);
      final res = await _dio.post<List<int>>(
        endpoint,
        data: {'prompt': prompt, 'size': '1024x1024'},
        options: Options(
          responseType: ResponseType.bytes,
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
      final data = res.data;
      if (data == null || data.isEmpty) {
        return const ImageGenResult.failure('Empty response from image service');
      }
      return ImageGenResult.success(Uint8List.fromList(data));
    } on DioException catch (e) {
      return ImageGenResult.failure('Network/API error: ${e.message}');
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
