import 'dart:typed_data';

import 'package:fieldnote_spike/src/wav.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List wavWith({
  int rate = 16000,
  int channels = 1,
  int bits = 16,
  List<int> extraChunk = const [],
}) {
  final pcm = Uint8List.fromList(List.generate(64, (i) => i));
  final wav = wavFromPcm(pcm);
  final view = ByteData.sublistView(wav)
    ..setUint16(22, channels, Endian.little)
    ..setUint32(24, rate, Endian.little)
    ..setUint16(34, bits, Endian.little);
  if (extraChunk.isEmpty) return Uint8List.view(view.buffer);
  return Uint8List.fromList([
    ...wav.sublist(0, 36),
    ...extraChunk,
    ...wav.sublist(36),
  ]);
}

void main() {
  test('reads back the samples of a WAV it wrote', () {
    final pcm = Uint8List.fromList(List.generate(320, (i) => i % 256));

    expect(pcmFromWav(wavFromPcm(pcm)), pcm);
  });

  test('skips chunks such as LIST between fmt and data', () {
    final list = [
      ..."LIST".codeUnits,
      3,
      0,
      0,
      0,
      1,
      2,
      3,
      0,
    ]; // odd size, padded
    expect(pcmFromWav(wavWith(extraChunk: list)), hasLength(64));
  });

  test(
    'rejects audio the speech package would misread, naming the actual format',
    () {
      expect(
        () => pcmFromWav(wavWith(rate: 44100)),
        throwsA(
          isFormatException.having(
            (e) => e.message,
            'message',
            contains('44100 Hz'),
          ),
        ),
      );
      expect(() => pcmFromWav(wavWith(channels: 2)), throwsFormatException);
      expect(() => pcmFromWav(wavWith(bits: 24)), throwsFormatException);
      expect(
        () => pcmFromWav(Uint8List.fromList('not a wav file'.codeUnits)),
        throwsFormatException,
      );
    },
  );

  test(
    'splits 65 s of audio into 30 s windows so nothing is silently truncated',
    () {
      final pcm = Uint8List(65 * bytesPerSecond);

      final windows = splitPcm(pcm, seconds: 30);

      expect(windows.map(pcmSeconds), [30, 30, 5]);
    },
  );
}
