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
}
