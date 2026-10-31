import 'package:fieldnote_spike/src/timing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  test(
    'measures prefill as time to first token and decode rate from later tokens',
    () async {
      final clock = FakeClock();
      final session = await FakeEngine(
        clock,
        prefillMs: 400,
        msPerChunk: 50,
      ).newSession(maxOutputTokens: 64);

      final result = await timeGeneration(
        submit: () => session.addPrompt('hi'),
        response: session.response,
        countTokens: session.countTokens,
        now: clock.call,
      );

      expect(result.text, 'one two three four five');
      expect(result.timing.timeToFirstToken, const Duration(milliseconds: 400));
      expect(result.timing.endToEnd, const Duration(milliseconds: 600));
      expect(result.timing.outputTokens, 5);
      // 4 tokens after the first, over 4 x 50 ms.
      expect(result.timing.decodeTokensPerSecond, closeTo(20, 1e-9));
    },
  );

  test(
    'an empty reply has no time to first token and no decode rate',
    () async {
      final clock = FakeClock();
      final timing = (await timeGeneration(
        submit: () async {},
        response: () => Stream.fromIterable(['', '']),
        countTokens: (_) async =>
            throw StateError('must not count an empty reply'),
        now: clock.call,
      )).timing;

      expect(timing.timeToFirstToken, isNull);
      expect(timing.decodeTokensPerSecond, isNull);
      expect(timing.outputTokens, 0);
      expect(timing.toJson()['timeToFirstTokenMs'], isNull);
    },
  );

  test('reports milliseconds in JSON', () {
    const timing = GenerationTiming(
      timeToFirstToken: Duration(microseconds: 1500),
      endToEnd: Duration(milliseconds: 10),
      firstToLastChunk: Duration(milliseconds: 8),
      outputTokens: 3,
      chunks: 3,
    );

    expect(timing.toJson(), containsPair('timeToFirstTokenMs', 1.5));
    expect(timing.toJson(), containsPair('decodeTokensPerSecond', 250.0));
  });
}
