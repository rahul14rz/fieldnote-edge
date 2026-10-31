import 'dart:async';

class MemoryReading {
  const MemoryReading({
    required this.anonymousBytes,
    required this.fileBackedBytes,
    required this.anonymousPeakBytes,
    required this.maxRssBytes,
  });

  /// Private dirty plus swapped memory on Android; phys_footprint on macOS.
  final int? anonymousBytes;

  /// Resident clean pages on Android (mapped model file, some GPU buffers).
  /// Null on macOS.
  final int? fileBackedBytes;

  /// Kernel lifetime high-water mark of phys_footprint. macOS only.
  final int? anonymousPeakBytes;

  /// Lifetime peak resident set size of the process (getrusage).
  final int maxRssBytes;
}

abstract interface class MemoryProbe {
  Future<MemoryReading> read();
}

int? _max(int? a, int? b) => a == null ? b : (b == null ? a : (a > b ? a : b));

/// The highest value seen for each field across a set of readings.
class MemoryPeaks {
  int? anonymousBytes;
  int? fileBackedBytes;
  int? anonymousPeakBytes;
  int? maxRssBytes;
  int samples = 0;

  void add(MemoryReading reading) {
    anonymousBytes = _max(anonymousBytes, reading.anonymousBytes);
    fileBackedBytes = _max(fileBackedBytes, reading.fileBackedBytes);
    anonymousPeakBytes = _max(anonymousPeakBytes, reading.anonymousPeakBytes);
    maxRssBytes = _max(maxRssBytes, reading.maxRssBytes);
    samples++;
  }

  Map<String, Object?> toJson() => {
    'sampledMaxAnonymousBytes': anonymousBytes,
    'sampledMaxFileBackedBytes': fileBackedBytes,
    'anonymousPeakBytes': anonymousPeakBytes,
    'maxRssBytes': maxRssBytes,
    'samples': samples,
  };
}

/// Runs [work] while reading memory before, every [interval], and after.
/// A null [interval] reads only before and after, so that timing runs are not
/// perturbed by the reads.
///
/// flutter_edge_ai_diagnostics advises reading no faster than once a second,
/// because each Android snapshot walks /proc and costs about 150 ms on a
/// low-end device.
Future<(T, MemoryPeaks)> sampleMemoryDuring<T>(
  MemoryProbe probe,
  Future<T> Function() work, {
  required Duration? interval,
}) async {
  final peaks = MemoryPeaks()..add(await probe.read());
  var reading = Future<void>.value();
  final timer = interval == null
      ? null
      : Timer.periodic(interval, (_) {
          reading = reading.then((_) async => peaks.add(await probe.read()));
        });
  try {
    final result = await work();
    return (result, peaks);
  } finally {
    timer?.cancel();
    await reading;
    peaks.add(await probe.read());
  }
}
