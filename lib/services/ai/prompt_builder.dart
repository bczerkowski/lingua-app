/// Builds the structured prompt sent to the image-generation backend.
class PromptBuilder {
  /// Shared photorealistic style block, so single and batch prompts stay
  /// identical in look.
  static const String _photoStyle =
      "The image must be strictly photorealistic, critically sharp, with a "
      "cinematic composition. Use natural, dynamic lighting, realistic "
      "textures, and natural colors. Shot on a high-end camera, 85mm lens. "
      "STRICTLY AVOID: 3D renders, illustrations, cartoonish elements, vector "
      "art, text, letters, words, watermarks, plastic-looking skin, or "
      "artificial AI aesthetics.";

  /// The illustration depicts the scene described by the example sentence
  /// (falling back to the word alone when there is no sentence).
  static String image(String targetWord, String exampleSentence) {
    // The scene comes from the example sentence; fall back to the bare word.
    final sentence = exampleSentence.trim();
    final scene = sentence.isNotEmpty ? sentence : targetWord.trim();
    return "A hyper-realistic, high-definition photograph perfectly "
        "illustrating the scene: '$scene'. $_photoStyle";
  }

  /// One prompt that asks for several separate photos at once — a numbered
  /// list of scenes with the shared style stated once up front. The returned
  /// images come back in the same order as [scenes], which the Image Studio
  /// batch slots rely on.
  static String imageBatch(List<String> scenes) {
    final n = scenes.length;
    final buf = StringBuffer()
      ..writeln("Generate $n separate, distinct photographs — one for each "
          "numbered item below. Return them as $n individual images in the "
          "same order, clearly separated (not a single collage).")
      ..writeln()
      ..writeln("Apply this exact style to EVERY image: $_photoStyle")
      ..writeln();
    for (var i = 0; i < n; i++) {
      buf.writeln("${i + 1}. ${scenes[i]}");
    }
    return buf.toString().trim();
  }

  /// Flat-design vector style — used for the in-app Pollinations generator,
  /// which handles clean illustrations far better than photorealism.
  ///
  /// Focuses on ONE iconic subject for the word (sentence only as light
  /// context) and hard-bans text-bearing objects — complex scenes with papers/
  /// signs are exactly what makes free models render garbled fake text.
  static String vector(String targetWord, String exampleSentence) {
    final word = targetWord.trim();
    final sentence = exampleSentence.trim();
    final context = sentence.isNotEmpty ? " (context: '$sentence')" : '';
    return "A simple, clean, minimalist flat-design vector illustration "
        "representing the word '$word'$context. One clear central subject, "
        "bold flat solid colors, smooth simple shapes, thick clean outlines, "
        "plain solid pastel background, lots of empty space, modern icon / "
        "sticker style. STRICTLY NO text, letters, words, numbers, captions, "
        "signs, posters, books, papers, labels, or logos of any kind.";
  }
}
