import 'dart:io';

import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';
import 'package:flutter_edge_ai_speech/flutter_edge_ai_speech.dart';

import '../app/app_controller.dart';
import '../pipeline/engines.dart';
import '../pipeline/wav.dart';
import 'model_catalog.dart';

Future<void> initializeEdgeAi() => FlutterEdgeAi.initialize(
  inferenceEngines: [const LiteRtLmEngine()],
  sttBackends: [LiteRtSttBackend()],
);

/// Downloads and activates the models in [ModelCatalog]. `install()` skips
/// files already on disk, so calling this again is cheap.
class EdgeAiModels implements ModelAvailability, ModelInstaller {
  @override
  bool get speechReady => FlutterEdgeAi.hasActiveStt();

  @override
  bool get summaryReady => FlutterEdgeAi.hasActiveModel();

  @override
  Future<void> installSummaryModel(
    void Function(int percent) onProgress,
  ) async {
    await FlutterEdgeAi.installModel(
          modelType: ModelType.gemma4,
          fileType: ModelFileType.litertlm,
        )
        .fromNetwork(ModelCatalog.summaryModelUrl)
        .withProgress(onProgress)
        .install();
  }

  @override
  Future<void> installSpeechModel(void Function(int percent) onProgress) async {
    await FlutterEdgeAi.installStt()
        .modelFromNetwork(ModelCatalog.speechModelUrl)
        .tokenizerFromNetwork(ModelCatalog.speechTokenizerUrl)
        .ofType(SttModelType.whisper)
        .withModelProgress(onProgress)
        .install();
  }
}

/// Whisper through flutter_edge_ai_speech, one 30-second window at a time,
/// because the package cuts longer audio without an error.
class WhisperSpeech implements SpeechToText {
  @override
  Future<String> transcribe(String wavPath, {required String language}) async {
    final pcm = pcmFromWav(await File(wavPath).readAsBytes());
    final recognizer = await FlutterEdgeAi.getActiveStt();
    try {
      final decode = ModelCatalog.whisperLanguage[language] ?? 'en';
      final parts = <String>[];
      for (final window in splitPcm(
        pcm,
        seconds: ModelCatalog.speechWindowSeconds,
      )) {
        final text = (await recognizer.transcribe(
          window,
          language: decode,
        )).trim();
        if (text.isNotEmpty) parts.add(text);
      }
      return parts.join(' ');
    } finally {
      await recognizer.close();
    }
  }
}

/// Gemma 4 E2B through LiteRT-LM with greedy decoding, so a rerun gives the
/// same answer and an invalid answer is a reason to escalate, not to retry.
class GemmaSummary implements SummaryModel {
  @override
  Future<String> generate(String prompt) async {
    final model = await FlutterEdgeAi.getActiveModel(
      maxTokens: ModelCatalog.summaryContextTokens,
    );
    final session = await model.createSession(
      topK: 1,
      maxOutputTokens: ModelCatalog.summaryMaxOutputTokens,
    );
    try {
      await session.addQueryChunk(Message(text: prompt, isUser: true));
      return await session.getResponse();
    } finally {
      await session.close();
    }
  }
}
