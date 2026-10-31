import 'dart:convert';
import 'dart:typed_data';

import 'package:fieldnote_spike/src/asr_benchmark.dart';
import 'package:fieldnote_spike/src/wav.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  final files = {
    'long.wav': wavFromPcm(Uint8List(65 * bytesPerSecond)),
    'short.wav': wavFromPcm(Uint8List(4 * bytesPerSecond)),
  };
  const items = [
    AsrItem(id: 'u1', language: 'ta-en', audio: 'long.wav'),
    AsrItem(id: 'u2', language: 'en', audio: 'short.wav'),
  ];

  Future<(List<AsrResult>, FakeTranscriber)> run({
    Map<String, String> decode = const {'ta-en': 'ta', 'en': 'en'},
  }) async {
    final transcriber = FakeTranscriber();
    final clock = FakeClock();
    final results = await runAsr(
      transcriber: transcriber,
      items: items,
      readFile: (path) async => files[path]!,
      decodeLanguage: decode,
      windowSeconds: 30,
      probe: FakeProbe([reading()]),
      memorySampleInterval: null,
      now: clock.call,
    );
    return (results, transcriber);
  }

  test(
    'transcribes long audio window by window with the mapped decode language',
    () async {
      final (results, transcriber) = await run();

      expect(transcriber.calls, [
        (30 * bytesPerSecond, 'ta'),
        (30 * bytesPerSecond, 'ta'),
        (5 * bytesPerSecond, 'ta'),
        (4 * bytesPerSecond, 'en'),
      ]);
      expect(results.first.windows, 3);
      expect(results.first.audioSeconds, 65);
      expect(results.first.text, 'window1 window2 window3');
    },
  );

  test('writes hypothesis lines in the format asr_eval reads', () async {
    final (results, _) = await run();

    expect(jsonDecode(results.last.toHypothesisLine()), {
      'id': 'u2',
      'text': 'window4',
    });
  });

  test(
    'refuses to start when a manifest language has no decode language',
    () async {
      expect(
        () => run(decode: const {'en': 'en'}),
        throwsA(
          isFormatException.having(
            (e) => e.message,
            'message',
            contains('ta-en'),
          ),
        ),
      );
    },
  );
}
