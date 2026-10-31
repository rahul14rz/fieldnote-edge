/// Speech-to-text on the phone. Implementations window long audio.
abstract interface class SpeechToText {
  Future<String> transcribe(String wavPath, {required String language});
}

/// A text model on the phone. Returns the raw answer.
abstract interface class SummaryModel {
  Future<String> generate(String prompt);
}

/// Which on-device models are installed and loadable.
abstract interface class ModelAvailability {
  bool get speechReady;
  bool get summaryReady;
}
