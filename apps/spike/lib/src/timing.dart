/// Monotonic time since an arbitrary origin. Tests pass a fake.
typedef Now = Duration Function();

Now stopwatchNow() {
  final stopwatch = Stopwatch()..start();
  return () => stopwatch.elapsed;
}

class GenerationTiming {
  const GenerationTiming({
    required this.timeToFirstToken,
    required this.endToEnd,
    required this.firstToLastChunk,
    required this.outputTokens,
    required this.chunks,
  });

  /// From submitting the prompt to the first non-empty chunk. Includes prefill.
  /// Null when the model produced no output.
  final Duration? timeToFirstToken;

  /// From submitting the prompt to the end of the response stream.
  final Duration endToEnd;

  /// From the first non-empty chunk to the last one.
  final Duration? firstToLastChunk;

  /// Counted with the model's own tokenizer after generation, because a
  /// streamed chunk is not guaranteed to be exactly one token.
  final int outputTokens;
  final int chunks;

  /// Decode rate: tokens after the first one, divided by the time between the
  /// first and last chunk. Null when there are fewer than two tokens or the
  /// interval is zero.
  double? get decodeTokensPerSecond {
    final interval = firstToLastChunk;
    if (outputTokens < 2 || interval == null || interval == Duration.zero) {
      return null;
    }
    return (outputTokens - 1) /
        (interval.inMicroseconds / Duration.microsecondsPerSecond);
  }

  Map<String, Object?> toJson() => {
    'timeToFirstTokenMs': timeToFirstToken?.inMicroseconds.toMs(),
    'endToEndMs': endToEnd.inMicroseconds.toMs(),
    'firstToLastChunkMs': firstToLastChunk?.inMicroseconds.toMs(),
    'outputTokens': outputTokens,
    'chunks': chunks,
    'decodeTokensPerSecond': decodeTokensPerSecond,
  };
}

extension on int {
  double toMs() => this / Duration.microsecondsPerMillisecond;
}

class TimedGeneration {
  const TimedGeneration(this.text, this.timing);
  final String text;
  final GenerationTiming timing;
}

/// Submits a prompt, consumes the streamed response, and times it.
Future<TimedGeneration> timeGeneration({
  required Future<void> Function() submit,
  required Stream<String> Function() response,
  required Future<int> Function(String text) countTokens,
  required Now now,
}) async {
  final start = now();
  await submit();
  final text = StringBuffer();
  Duration? first;
  Duration? last;
  var chunks = 0;
  await for (final chunk in response()) {
    if (chunk.isEmpty) continue;
    final at = now();
    first ??= at;
    last = at;
    chunks++;
    text.write(chunk);
  }
  final end = now();
  final output = text.toString();
  return TimedGeneration(
    output,
    GenerationTiming(
      timeToFirstToken: first == null ? null : first - start,
      endToEnd: end - start,
      firstToLastChunk: first == null ? null : last! - first,
      outputTokens: output.isEmpty ? 0 : await countTokens(output),
      chunks: chunks,
    ),
  );
}
