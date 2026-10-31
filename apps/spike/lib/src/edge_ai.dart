import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_diagnostics/flutter_edge_ai_diagnostics.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';
import 'package:flutter_edge_ai_speech/flutter_edge_ai_speech.dart';

import 'asr_benchmark.dart';
import 'config.dart';
import 'gemma_asr_prompt.dart';
import 'llm_benchmark.dart';
import 'memory.dart';
import 'wav.dart';

Future<void> initializeEdgeAi() => FlutterEdgeAi.initialize(
  inferenceEngines: [const LiteRtLmEngine()],
  sttBackends: [LiteRtSttBackend()],
);

PreferredBackend _backend(Backend backend) => switch (backend) {
  Backend.cpu => PreferredBackend.cpu,
  Backend.gpu => PreferredBackend.gpu,
};

/// Installs a local `.litertlm` file and loads it. The returned model reports
/// the backend that actually loaded, which can differ from the one requested.
Future<InferenceModel> loadLitertLm({
  required String path,
  required Backend backend,
  required int contextTokens,
  bool supportAudio = false,
}) async {
  await FlutterEdgeAi.installModel(
    modelType: ModelType.gemma4,
    fileType: ModelFileType.litertlm,
  ).fromFile(path).install();
  return FlutterEdgeAi.getActiveModel(
    maxTokens: contextTokens,
    preferredBackend: _backend(backend),
    supportAudio: supportAudio,
  );
}

class EdgeAiLlmEngine implements LlmEngine {
  EdgeAiLlmEngine(this.model);

  final InferenceModel model;

  /// topK 1 decodes greedily, so every repetition of a prompt produces the
  /// same output length and the timings are comparable.
  @override
  Future<LlmSession> newSession({required int maxOutputTokens}) async =>
      _Session(
        await model.createSession(topK: 1, maxOutputTokens: maxOutputTokens),
      );
}

class _Session implements LlmSession {
  _Session(this.session);

  final InferenceModelSession session;

  @override
  Future<void> addPrompt(String text) =>
      session.addQueryChunk(Message(text: text, isUser: true));

  @override
  Stream<String> response() => session.getResponseAsync();

  @override
  Future<int> countTokens(String text) => session.sizeInTokens(text);

  @override
  Future<void> close() => session.close();
}

Future<SpeechRecognizer> loadWhisper({
  required String modelPath,
  required String tokenizerPath,
  required Backend backend,
}) async {
  await FlutterEdgeAi.installStt()
      .modelFromFile(modelPath)
      .tokenizerFromFile(tokenizerPath)
      .ofType(SttModelType.whisper)
      .install();
  return FlutterEdgeAi.getActiveStt(preferredBackend: _backend(backend));
}

class WhisperTranscriber implements Transcriber {
  WhisperTranscriber(this.recognizer);

  final SpeechRecognizer recognizer;

  @override
  Future<String> transcribe(Uint8List pcm, {required String language}) =>
      recognizer.transcribe(pcm, language: language);
}

/// Sends each audio window to Gemma as a WAV attachment with the model
/// card's ASR prompt. The model card limits audio to 30 seconds per input.
/// A new chat per window keeps windows independent.
class GemmaAudioTranscriber implements Transcriber {
  GemmaAudioTranscriber(this.model);

  final InferenceModel model;

  @override
  Future<String> transcribe(Uint8List pcm, {required String language}) async {
    final chat = await model.createChat(
      supportAudio: true,
      topK: 1,
      maxOutputTokens: 512,
    );
    try {
      await chat.addQueryChunk(
        Message(
          text: gemmaAsrPrompt(language),
          isUser: true,
          audioBytes: wavFromPcm(pcm),
        ),
      );
      return switch (await chat.generateChatResponse()) {
        TextResponse(:final token) => token,
        final other => throw StateError(
          'expected a text transcript, got ${other.runtimeType}',
        ),
      };
    } finally {
      await chat.close();
    }
  }
}

class DiagnosticsMemoryProbe implements MemoryProbe {
  @override
  Future<MemoryReading> read() async {
    final snapshot = FlutterEdgeAiDiagnostics.isSupported
        ? await FlutterEdgeAiDiagnostics.memorySnapshot()
        : null;
    return MemoryReading(
      anonymousBytes: snapshot?.anonymousBytes,
      fileBackedBytes: snapshot?.fileBackedBytes,
      anonymousPeakBytes: snapshot?.anonymousPeakBytes,
      maxRssBytes: ProcessInfo.maxRss,
    );
  }
}
