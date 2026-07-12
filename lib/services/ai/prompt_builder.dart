/// Builds the structured prompt sent to the image-generation backend.
class PromptBuilder {
  /// The illustration depicts the scene described by the example sentence
  /// (falling back to the word alone when there is no sentence).
  static String image(String targetWord, String exampleSentence) {
    // The scene comes from the example sentence; fall back to the bare word.
    final sentence = exampleSentence.trim();
    final scene = sentence.isNotEmpty ? sentence : targetWord.trim();
    return "A hyper-realistic, high-definition photograph perfectly "
        "illustrating the scene: '$scene'. The image must be strictly "
        "photorealistic, critically sharp, with a cinematic composition. "
        "Use natural, dynamic lighting, realistic textures, and natural "
        "colors. Shot on a high-end camera, 85mm lens. STRICTLY AVOID: 3D "
        "renders, illustrations, cartoonish elements, vector art, text, "
        "letters, words, watermarks, plastic-looking skin, or artificial AI "
        "aesthetics.";
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
