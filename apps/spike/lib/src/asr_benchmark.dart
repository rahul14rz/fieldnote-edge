import 'dart:convert';
import 'dart:typed_data';

import 'memory.dart';
import 'timing.dart';
import 'wav.dart';

abstract interface class Transcriber {
  Future<String> transcribe(Uint8List pcm, {required String language});
}

class AsrItem {
  const AsrItem({
    required this.id,
    required this.language,
    required this.audio,
  });

  factory AsrItem.fromJson(Map<String, Object?> json) => AsrItem(
    id: json['id'] as String,
    language: json['language'] as String,
    audio: json['audio'] as String,
  );

  final String id;

  /// Language code used by benchmarks/evaluation, for example `ta-en`.
  final String language;

  /// WAV path relative to the work directory.
  final String audio;
}

class AsrResult {
  const AsrResult({
    required this.item,
    required this.decodeLanguage,
    required this.audioSeconds,
    required this.windows,
    required this.elapsed,
    required this.memory,
    required this.text,
  });

  final AsrItem item;
  final String decodeLanguage;
  final double audioSeconds;
  final int windows;
  final Duration elapsed;
  final MemoryPeaks memory;
  final String text;

  /// Processing time divided by audio duration. Below 1 is faster than real time.
  double get realTimeFactor =>
      elapsed.inMicroseconds / Duration.microsecondsPerSecond / audioSeconds;

  Map<String, Object?> toJson() => {
    'id': item.id,
    'language': item.language,
    'decodeLanguage': decodeLanguage,
    'audioSeconds': audioSeconds,
    'windows': windows,
    'elapsedMs': elapsed.inMicroseconds / Duration.microsecondsPerMillisecond,
    'realTimeFactor': realTimeFactor,
    'memory': memory.toJson(),
    'text': text,
  };

  /// One line of the hypotheses file read by `python3 -m asr_eval`.
  String toHypothesisLine() => jsonEncode({'id': item.id, 'text': text});
}

/// Transcribes each item window by window and joins the windows with a space.
Future<List<AsrResult>> runAsr({
  required Transcriber transcriber,
  required List<AsrItem> items,
  required Future<Uint8List> Function(String path) readFile,
  required Map<String, String> decodeLanguage,
  required int windowSeconds,
  required MemoryProbe probe,
  required Duration? memorySampleInterval,
  required Now now,
  void Function(String message)? log,
}) async {
  final missing = {for (final i in items) i.language}
      .difference(decodeLanguage.keys.toSet());
  if (missing.isNotEmpty) {
    throw FormatException(
      'decodeLanguage has no entry for: ${missing.join(', ')}',
    );
  }
  final results = <AsrResult>[];
  for (final item in items) {
    log?.call('transcribe ${item.id} (${item.language})');
    final pcm = pcmFromWav(await readFile(item.audio));
    final windows = splitPcm(pcm, seconds: windowSeconds);
    final language = decodeLanguage[item.language]!;
    final start = now();
    final (texts, memory) = await sampleMemoryDuring(
      probe,
      interval: memorySampleInterval,
      () async {
        return [
          for (final w in windows)
            (await transcriber.transcribe(w, language: language)).trim(),
        ];
      },
    );
    results.add(
      AsrResult(
        item: item,
        decodeLanguage: language,
        audioSeconds: pcmSeconds(pcm),
        windows: windows.length,
        elapsed: now() - start,
        memory: memory,
        text: texts.where((t) => t.isNotEmpty).join(' '),
      ),
    );
  }
  return results;
}
