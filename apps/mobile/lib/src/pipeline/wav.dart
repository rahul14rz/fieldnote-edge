import 'dart:typed_data';

const sampleRate = 16000;
const bytesPerSecond = sampleRate * 2;

/// Returns the samples of a 16 kHz, mono, 16-bit PCM WAV file.
///
/// Throws [FormatException] for any other format, because
/// flutter_edge_ai_speech does not resample or convert.
Uint8List pcmFromWav(Uint8List wav) {
  if (wav.length < 12 ||
      String.fromCharCodes(wav, 0, 4) != 'RIFF' ||
      String.fromCharCodes(wav, 8, 12) != 'WAVE') {
    throw const FormatException('not a RIFF/WAVE file');
  }
  final view = ByteData.sublistView(wav);
  var offset = 12;
  var formatChecked = false;
  while (offset + 8 <= wav.length) {
    final id = String.fromCharCodes(wav, offset, offset + 4);
    final size = view.getUint32(offset + 4, Endian.little);
    final start = offset + 8;
    if (id == 'fmt ') {
      final format = view.getUint16(start, Endian.little);
      final channels = view.getUint16(start + 2, Endian.little);
      final rate = view.getUint32(start + 4, Endian.little);
      final bits = view.getUint16(start + 14, Endian.little);
      if (format != 1 || channels != 1 || rate != sampleRate || bits != 16) {
        throw FormatException(
          'expected PCM 16 kHz mono 16-bit, got format $format, '
          '$channels channel(s), $rate Hz, $bits-bit',
        );
      }
      formatChecked = true;
    } else if (id == 'data') {
      if (!formatChecked) {
        throw const FormatException('data chunk before fmt chunk');
      }
      final end = start + size > wav.length ? wav.length : start + size;
      return Uint8List.sublistView(wav, start, end);
    }
    offset = start + size + (size & 1);
  }
  throw const FormatException('WAV file has no data chunk');
}

/// Wraps raw 16 kHz mono 16-bit PCM in a 44-byte WAV header.
Uint8List wavFromPcm(Uint8List pcm) {
  final header = ByteData(44)
    ..setUint32(0, 0x46464952, Endian.little) // RIFF
    ..setUint32(4, 36 + pcm.length, Endian.little)
    ..setUint32(8, 0x45564157, Endian.little) // WAVE
    ..setUint32(12, 0x20746d66, Endian.little) // fmt
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, sampleRate, Endian.little)
    ..setUint32(28, bytesPerSecond, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little)
    ..setUint32(36, 0x61746164, Endian.little) // data
    ..setUint32(40, pcm.length, Endian.little);
  return Uint8List.fromList([...header.buffer.asUint8List(), ...pcm]);
}

/// Splits PCM into consecutive windows of at most [seconds].
///
/// flutter_edge_ai_speech zero-pads shorter audio and silently truncates
/// longer audio to the model window (30 s for Whisper), so long recordings
/// must be split before transcription.
List<Uint8List> splitPcm(Uint8List pcm, {required int seconds}) {
  if (seconds <= 0) {
    throw ArgumentError.value(seconds, 'seconds', 'must be positive');
  }
  final window = seconds * bytesPerSecond;
  return [
    for (var start = 0; start < pcm.length; start += window)
      Uint8List.sublistView(
        pcm,
        start,
        start + window > pcm.length ? pcm.length : start + window,
      ),
  ];
}

double pcmSeconds(Uint8List pcm) => pcm.length / bytesPerSecond;
