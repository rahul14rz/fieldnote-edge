import 'dart:convert';
import 'dart:io';

import 'package:fieldnote_spike/src/config.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> example(String name) =>
    jsonDecode(File('examples/$name').readAsStringSync())
        as Map<String, Object?>;

void main() {
  test('every example config in the runbook parses', () {
    final names = Directory('examples')
        .listSync()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.endsWith('.json'));
    expect(names, isNotEmpty);
    for (final name in names) {
      expect(
        () => SpikeConfig.fromJson(example(name)),
        returnsNormally,
        reason: name,
      );
    }
  });

  test('an LLM config exposes the model, backend and run plan', () {
    final config = SpikeConfig.fromJson(
      example('llm-gemma4-e2b-gpu-memory.json'),
    ) as LlmConfig;

    expect(config.backend, Backend.gpu);
    expect(config.repetitions, 3);
    expect(config.memorySampleInterval, const Duration(seconds: 1));
  });

  test('a timing config reads memory only before and after', () {
    expect(
      SpikeConfig.fromJson(example('llm-gemma4-e2b-gpu-timing.json'))
          .memorySampleInterval,
      isNull,
    );
  });

  test('code-switched languages map to one decode language each', () {
    final config = SpikeConfig.fromJson(
      example('asr-whisper-base-timing.json'),
    ) as AsrConfig;

    expect(config.decodeLanguage['ta-en'], 'ta');
  });

  group('rejects', () {
    Map<String, Object?> asr() => example('asr-whisper-base-timing.json');

    test('a whisper config without a tokenizer', () {
      final json = asr();
      (json['asr'] as Map<String, Object?>).remove('tokenizerFile');
      expect(
        () => SpikeConfig.fromJson(json),
        throwsA(
          isFormatException.having(
            (e) => e.message,
            'message',
            contains('tokenizerFile'),
          ),
        ),
      );
    });

    test('sampling memory faster than once a second', () {
      expect(
        () => SpikeConfig.fromJson({...asr(), 'memorySampleIntervalMs': 200}),
        throwsFormatException,
      );
    });

    test('an unknown mode or backend', () {
      expect(
        () => SpikeConfig.fromJson({...asr(), 'mode': 'vision'}),
        throwsFormatException,
      );
      final json = asr();
      (json['asr'] as Map<String, Object?>)['backend'] = 'npu';
      expect(() => SpikeConfig.fromJson(json), throwsFormatException);
    });
  });
}
