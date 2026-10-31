import 'package:fieldnote_spike/src/llm_benchmark.dart';
import 'package:fieldnote_spike/src/prompt_set.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  const promptSet = PromptSet(
    version: 'test',
    cases: [
      PromptCase(id: 'a', maxOutputTokens: 16, prompt: 'prompt a'),
      PromptCase(id: 'b', maxOutputTokens: 32, prompt: 'prompt b b'),
    ],
  );

  Future<(List<PromptRun>, FakeEngine)> run({
    int repetitions = 2,
    int warmupRuns = 1,
  }) async {
    final clock = FakeClock();
    final engine = FakeEngine(clock);
    final runs = await runPromptSet(
      engine: engine,
      promptSet: promptSet,
      repetitions: repetitions,
      warmupRuns: warmupRuns,
      probe: FakeProbe([reading(anonymous: 10, maxRss: 20)]),
      memorySampleInterval: null,
      now: clock.call,
    );
    return (runs, engine);
  }

  test('runs warmups first, then every case once per repetition', () async {
    final (runs, _) = await run();

    expect(runs.map((r) => (r.caseId, r.repetition, r.warmup)), [
      ('a', 1, true),
      ('a', 1, false),
      ('b', 1, false),
      ('a', 2, false),
      ('b', 2, false),
    ]);
  });

  test(
    'gives every run a fresh session with that case limit, and closes it',
    () async {
      final (_, engine) = await run(repetitions: 1, warmupRuns: 0);

      expect(
        engine.sessions.map(
          (s) => (s.prompts.join('|'), s.maxOutputTokens, s.closed),
        ),
        [('prompt a', 16, true), ('prompt b b', 32, true)],
      );
    },
  );

  test('records prompt size, timing, memory and output for each run', () async {
    final (runs, _) = await run(repetitions: 1, warmupRuns: 0);
    final json = runs.last.toJson();

    expect(json['promptTokens'], 3);
    expect(json['outputTokens'], 5);
    expect(json['timeToFirstTokenMs'], 100.0);
    expect(json['output'], 'one two three four five');
    expect((json['memory']! as Map)['maxRssBytes'], 20);
  });
}
