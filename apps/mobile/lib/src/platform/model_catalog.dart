/// The on-device models Milestone 1 installs. These are the spike's
/// candidates, not a measured choice: change them here after the go/no-go
/// table in docs/spike/RUNBOOK.md is filled in. All three files were listed by
/// the Hugging Face API on 2026-11-01 and are Apache 2.0
/// (docs/spike/findings.md).
abstract final class ModelCatalog {
  static const summaryModelUrl =
      'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm';
  static const speechModelUrl =
      'https://huggingface.co/litert-community/whisper-base/resolve/main/whisper_base_30s_i8.tflite';
  static const speechTokenizerUrl =
      'https://huggingface.co/openai/whisper-base/resolve/main/tokenizer.json';

  /// Context window for summaries. Gemma 4 E2B supports 128K tokens, but
  /// memory on the phone is not yet measured; larger transcripts should be
  /// routed to the Mac once the limit is known.
  static const summaryContextTokens = 8192;
  static const summaryMaxOutputTokens = 2048;

  /// Whisper's fixed window in flutter_edge_ai_speech. Longer audio is cut.
  static const speechWindowSeconds = 30;

  /// Whisper decode language for each recording language. Code-switched
  /// speech has no single code; the base language is used, as in the spike.
  static const whisperLanguage = {
    'en': 'en',
    'ta': 'ta',
    'ml': 'ml',
    'hi': 'hi',
    'ta-en': 'ta',
    'ml-en': 'ml',
    'hi-en': 'hi',
  };
}
