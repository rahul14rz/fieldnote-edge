import 'package:fieldnote_spike/src/memory.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  test('keeps the highest value of each field and tolerates fields a platform does not report', () {
    final peaks = MemoryPeaks()
      ..add(reading(anonymous: 100, maxRss: 500))
      ..add(reading(anonymous: 300, fileBacked: 50, maxRss: 400))
      ..add(reading(anonymous: 200, fileBacked: 70, maxRss: 600));

    expect(peaks.toJson(), {
      'sampledMaxAnonymousBytes': 300,
      'sampledMaxFileBackedBytes': 70,
      'anonymousPeakBytes': null,
      'maxRssBytes': 600,
      'samples': 3,
    });
  });

  test(
    'without an interval, memory is read only before and after the work',
    () async {
      final probe = FakeProbe([reading(anonymous: 1), reading(anonymous: 9)]);

      final (value, peaks) = await sampleMemoryDuring(
        probe,
        interval: null,
        () async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return 'done';
        },
      );

      expect(value, 'done');
      expect(probe.reads, 2);
      expect(peaks.anonymousBytes, 9);
    },
  );

  test('with an interval, memory is also read while the work runs', () async {
    final probe = FakeProbe([reading(anonymous: 1)]);

    await sampleMemoryDuring(
      probe,
      interval: const Duration(milliseconds: 10),
      () async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      },
    );

    expect(probe.reads, greaterThan(4));
  });
}
