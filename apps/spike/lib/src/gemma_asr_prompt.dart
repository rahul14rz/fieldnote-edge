/// The ASR prompt from the Gemma 4 E2B model card
/// (https://huggingface.co/google/gemma-4-E2B-it, section "Audio"), with the
/// language name filled in. [language] is a name such as "Tamil", or
/// "Tamil and English" for code-switched speech.
String gemmaAsrPrompt(String language) {
  if (language.trim().length < 3) {
    throw ArgumentError.value(
      language,
      'language',
      'use a language name such as "Tamil", not a code',
    );
  }
  return 'Transcribe the following speech segment in $language into $language text.\n'
      '\n'
      'Follow these specific instructions for formatting the answer:\n'
      '* Only output the transcription, with no newlines.\n'
      '* When transcribing numbers, write the digits, i.e. write 1.7 and not one point seven, '
      'and write 3 instead of three.';
}
