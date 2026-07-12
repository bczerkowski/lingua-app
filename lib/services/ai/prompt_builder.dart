/// Builds the structured prompt sent to the image-generation backend.
class PromptBuilder {
  /// The illustration depicts the scene described by the example sentence
  /// (falling back to the word alone when there is no sentence).
  static String image(String targetWord, String exampleSentence) {
    final sentence = exampleSentence.trim();
    const style = "Realistic photograph, photorealistic, natural lighting, "
        "sharp focus, high detail, shot on a DSLR camera. "
        "No text, no letters, no words, no captions, no watermark.";
    if (sentence.isEmpty) {
      return "A realistic photograph clearly showing '$targetWord'. $style";
    }
    return "A realistic photograph depicting this scene: \"$sentence\". "
        "Show what is happening in the sentence, with '$targetWord' as the "
        "focus. $style";
  }
}
