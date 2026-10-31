import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'asr_benchmark.dart';
import 'config.dart';
import 'edge_ai.dart';
import 'llm_benchmark.dart';
import 'memory.dart';
import 'prompt_set.dart';
import 'run_record.dart';
import 'timing.dart';

const configFileName = 'spike_config.json';

/// Reads `spike_config.json` from [workDir], runs the measurement it names,
/// and writes `results/<runId>.json` (plus a hypotheses file for ASR runs).
/// Returns the result file.
Future<File> runFromWorkDir(
  Directory workDir, {
  required void Function(String) log,
}) async {
  final configFile = File('${workDir.path}/$configFileName');
  if (!configFile.existsSync()) {
    throw FileSystemException(
      'no $configFileName in the work directory',
      configFile.path,
    );
  }
  final config = SpikeConfig.fromJson(
    jsonDecode(await configFile.readAsString()) as Map<String, Object?>,
  );
  final resultsDir = Directory('${workDir.path}/results')
    ..createSync(recursive: true);
  final startedAt = DateTime.now();
  final probe = DiagnosticsMemoryProbe();
  final now = stopwatchNow();
  String resolve(String relative) => '${workDir.path}/$relative';

  await initializeEdgeAi();

  switch (config) {
    case LlmConfig():
      final promptSet = PromptSet.fromJson(
        jsonDecode(await rootBundle.loadString('assets/prompt_set.json'))
            as Map<String, Object?>,
        schema: await rootBundle.loadString(
          'assets/meeting-summary.schema.json',
        ),
      );
      final before = await probe.read();
      final loadStart = now();
      final model = await loadLitertLm(
        path: resolve(config.modelFile),
        backend: config.backend,
        contextTokens: config.contextTokens,
      );
      final load = await _load(
        config.backend,
        model.activeBackend?.name,
        now() - loadStart,
        before,
        probe,
      );
      log(
        'loaded ${config.modelId}: requested ${config.backend.name}, active ${load.activeBackend}',
      );
      final runs = await runPromptSet(
        engine: EdgeAiLlmEngine(model),
        promptSet: promptSet,
        repetitions: config.repetitions,
        warmupRuns: config.warmupRuns,
        probe: probe,
        memorySampleInterval: config.memorySampleInterval,
        now: now,
        log: log,
      );
      await model.close();
      final runId = runIdFor(startedAt, 'llm');
      return _write(
        resultsDir,
        runId,
        llmRunRecord(
          config: config,
          runId: runId,
          startedAt: startedAt,
          finishedAt: DateTime.now(),
          load: load,
          promptSetVersion: promptSet.version,
          runs: runs,
        ),
      );

    case AsrConfig():
      final items = [
        for (final line in await File(resolve(config.manifest)).readAsLines())
          if (line.trim().isNotEmpty)
            AsrItem.fromJson(jsonDecode(line) as Map<String, Object?>),
      ];
      final before = await probe.read();
      final loadStart = now();
      final Transcriber transcriber;
      final String? activeBackend;
      switch (config.engine) {
        case AsrEngine.whisper:
          final recognizer = await loadWhisper(
            modelPath: resolve(config.modelFile),
            tokenizerPath: resolve(config.tokenizerFile!),
            backend: config.backend,
          );
          transcriber = WhisperTranscriber(recognizer);
          activeBackend = null;
        case AsrEngine.gemmaAudio:
          final model = await loadLitertLm(
            path: resolve(config.modelFile),
            backend: config.backend,
            contextTokens: 4096,
            supportAudio: true,
          );
          transcriber = GemmaAudioTranscriber(model);
          activeBackend = model.activeBackend?.name;
      }
      final load = await _load(
        config.backend,
        activeBackend,
        now() - loadStart,
        before,
        probe,
      );
      log('loaded ${config.modelId} (${config.engine.name})');
      final results = await runAsr(
        transcriber: transcriber,
        items: items,
        readFile: (path) => File(resolve(path)).readAsBytes(),
        decodeLanguage: config.decodeLanguage,
        windowSeconds: config.windowSeconds,
        probe: probe,
        memorySampleInterval: config.memorySampleInterval,
        now: now,
        log: log,
      );
      final runId = runIdFor(startedAt, 'asr');
      await File('${resultsDir.path}/$runId.hypotheses.jsonl').writeAsString(
        '${results.map((r) => r.toHypothesisLine()).join('\n')}\n',
      );
      return _write(
        resultsDir,
        runId,
        asrRunRecord(
          config: config,
          runId: runId,
          startedAt: startedAt,
          finishedAt: DateTime.now(),
          load: load,
          results: results,
        ),
      );
  }
}

Future<ModelLoad> _load(
  Backend requested,
  String? active,
  Duration loadTime,
  MemoryReading before,
  MemoryProbe probe,
) async => ModelLoad(
  requestedBackend: requested.name,
  activeBackend: active,
  loadTime: loadTime,
  before: before,
  after: await probe.read(),
);

Future<File> _write(Directory dir, String runId, Map<String, Object?> record) =>
    File('${dir.path}/$runId.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(record));
