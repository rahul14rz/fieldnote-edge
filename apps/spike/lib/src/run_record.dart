import 'dart:io';

import 'asr_benchmark.dart';
import 'config.dart';
import 'llm_benchmark.dart';
import 'memory.dart';

/// Versions resolved in pubspec.lock. A test fails if they drift apart.
const edgeAiPackageVersions = {
  'flutter_edge_ai': '2.5.4',
  'flutter_edge_ai_diagnostics': '0.5.0',
  'flutter_edge_ai_litertlm': '1.19.0',
  'flutter_edge_ai_speech': '0.5.12',
};

/// Version of the JSON written by the spike. Matches
/// benchmarks/results/run-record.schema.json.
const runRecordSchemaVersion = 1;

class ModelLoad {
  const ModelLoad({
    required this.requestedBackend,
    required this.activeBackend,
    required this.loadTime,
    required this.before,
    required this.after,
  });

  final String requestedBackend;

  /// What the engine reports it loaded, or null if it does not say.
  final String? activeBackend;
  final Duration loadTime;
  final MemoryReading before;
  final MemoryReading after;

  Map<String, Object?> toJson() => {
    'requestedBackend': requestedBackend,
    'activeBackend': activeBackend,
    'loadMs': loadTime.inMicroseconds / Duration.microsecondsPerMillisecond,
    'memoryBeforeLoad': readingJson(before),
    'memoryAfterLoad': readingJson(after),
  };
}

Map<String, Object?> readingJson(MemoryReading r) => {
  'anonymousBytes': r.anonymousBytes,
  'fileBackedBytes': r.fileBackedBytes,
  'anonymousPeakBytes': r.anonymousPeakBytes,
  'maxRssBytes': r.maxRssBytes,
};

Map<String, Object?> _envelope({
  required SpikeConfig config,
  required String runId,
  required DateTime startedAt,
  required DateTime finishedAt,
  required ModelLoad load,
}) => {
  'schemaVersion': runRecordSchemaVersion,
  'runId': runId,
  'startedAt': startedAt.toUtc().toIso8601String(),
  'finishedAt': finishedAt.toUtc().toIso8601String(),
  'device': {
    'label': config.deviceLabel,
    'os': Platform.operatingSystem,
    'osVersion': Platform.operatingSystemVersion,
    'processors': Platform.numberOfProcessors,
  },
  'packages': edgeAiPackageVersions,
  'config': config.raw,
  'model': load.toJson(),
};

Map<String, Object?> llmRunRecord({
  required LlmConfig config,
  required String runId,
  required DateTime startedAt,
  required DateTime finishedAt,
  required ModelLoad load,
  required String promptSetVersion,
  required List<PromptRun> runs,
}) => {
  ..._envelope(
    config: config,
    runId: runId,
    startedAt: startedAt,
    finishedAt: finishedAt,
    load: load,
  ),
  'mode': 'llm',
  'promptSetVersion': promptSetVersion,
  'runs': [for (final r in runs) r.toJson()],
};

Map<String, Object?> asrRunRecord({
  required AsrConfig config,
  required String runId,
  required DateTime startedAt,
  required DateTime finishedAt,
  required ModelLoad load,
  required List<AsrResult> results,
}) => {
  ..._envelope(
    config: config,
    runId: runId,
    startedAt: startedAt,
    finishedAt: finishedAt,
    load: load,
  ),
  'mode': 'asr',
  'results': [for (final r in results) r.toJson()],
};

/// A file-name-safe run id, for example `20261031T081500Z-llm`.
String runIdFor(DateTime startedAt, String mode) {
  final t = startedAt
      .toUtc()
      .toIso8601String()
      .replaceAll(RegExp(r'[-:]'), '')
      .split('.')
      .first;
  return '${t}Z-$mode';
}
