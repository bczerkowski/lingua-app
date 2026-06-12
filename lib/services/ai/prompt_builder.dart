/// Builds the structured prompt sent to the image-generation backend.
class PromptBuilder {
  static String image(String targetWord, String exampleSentence) =>
      "Create a clear, minimalist, educational illustration focusing on the "
      "concept of $targetWord as used in the sentence: '$exampleSentence'. "
      "Simple flat style, neutral background, no text in the image.";
}
