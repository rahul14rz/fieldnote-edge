import 'memory.dart';
import 'prompt_set.dart';
import 'timing.dart';

abstract interface class LlmSession {
  Future<void> addPrompt(String text);
  Stream<String> response();
  Future<int> countTokens(String text);
  Future<void> close();
}

abstract interface class LlmEngine {
  Future<LlmSession> newSession({required int maxOutputTokens});
}

class PromptRun {
  const PromptRun({
    required this.caseId,
    required this.repetition,
    required this.warmup,
    required this.promptTokens,
    required this.timing,
    required this.memory,
    required this.output,
  });

  final String caseId;

  /// 1-based. Warmup runs count separately from 1.
  final int repetition;
  final bool warmup;
  final int promptTokens;
  final GenerationTiming timing;
  final MemoryPeaks memory;
  final String output;

  Map<String, Object?> toJson() => {
    'caseId': caseId,
    'repetition': repetition,
    'warmup': warmup,
    'promptTokens': promptTokens,
    ...timing.toJson(),
    'memory': memory.toJson(),
    'output': output,
  };
}

/// Runs every prompt case [repetitions] times, after [warmupRuns] untimed
/// passes over the first case. Each run uses a fresh session, so no run sees
/// another run's conversation.
Future<List<PromptRun>> runPromptSet({
  required LlmEngine engine,
  required PromptSet promptSet,
  required int repetitions,
  required int warmupRuns,
  required MemoryProbe probe,
  required Duration? memorySampleInterval,
  required Now now,
  void Function(String message)? log,
}) async {
  final plan = [
    for (var i = 1; i <= warmupRuns; i++) (promptSet.cases.first, i, true),
    for (var r = 1; r <= repetitions; r++)
      for (final c in promptSet.cases) (c, r, false),
  ];
  final runs = <PromptRun>[];
  for (final (promptCase, repetition, warmup) in plan) {
    log?.call('${warmup ? 'warmup' : 'run'} ${promptCase.id} #$repetition');
    final session = await engine.newSession(
      maxOutputTokens: promptCase.maxOutputTokens,
    );
    try {
      final promptTokens = await session.countTokens(promptCase.prompt);
      final (generation, memory) = await sampleMemoryDuring(
        probe,
        interval: memorySampleInterval,
        () => timeGeneration(
          submit: () => session.addPrompt(promptCase.prompt),
          response: session.response,
          countTokens: session.countTokens,
          now: now,
        ),
      );
      runs.add(
        PromptRun(
          caseId: promptCase.id,
          repetition: repetition,
          warmup: warmup,
          promptTokens: promptTokens,
          timing: generation.timing,
          memory: memory,
          output: generation.text,
        ),
      );
    } finally {
      await session.close();
    }
  }
  return runs;
}
