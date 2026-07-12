/// Builds the structured prompt sent to the image-generation backend.
class PromptBuilder {
  /// The illustration depicts the scene described by the example sentence
  /// (falling back to the word alone when there is no sentence).
  static String image(String targetWord, String exampleSentence) {
    final sentence = exampleSentence.trim();
    if (sentence.isEmpty) {
      return "A clear, simple, minimalist illustration of the concept "
          "'$targetWord'. Flat vector style, soft neutral background, "
          "no text, no letters, no words, no captions.";
    }
    return "A clear, simple, minimalist illustration depicting this scene: "
        "\"$sentence\". Show what is happening in the sentence, with "
        "'$targetWord' as the focus. Flat vector style, soft neutral "
        "background, no text, no letters, no words, no captions.";
  }
}
