import 'dart:convert';
import 'dart:io';

import 'package:fieldnote_spike/src/config.dart';
import 'package:fieldnote_spike/src/llm_benchmark.dart';
import 'package:fieldnote_spike/src/prompt_set.dart';
import 'package:fieldnote_spike/src/run_record.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

/// Checks the JSON Schema keywords that run-record.schema.json uses: type,
/// required, properties, items, enum, const, additionalProperties, allOf with
/// if/then. Returns one message per violation.
List<String> violations(
  Object? value,
  Map<String, Object?> schema, [
  String path = r'$',
]) {
  final errors = <String>[];
  bool isType(String t) => switch (t) {
    'object' => value is Map,
    'array' => value is List,
    'string' => value is String,
    'integer' => value is int,
    'number' => value is num,
    'boolean' => value is bool,
    'null' => value == null,
    _ => throw UnsupportedError('type $t'),
  };
  final type = schema['type'];
  if (type != null &&
      !(type is List
          ? type.cast<String>().any(isType)
          : isType(type as String))) {
    return ['$path: expected $type, got ${value.runtimeType}'];
  }
  if (schema.containsKey('const') && schema['const'] != value) {
    errors.add('$path: expected ${schema['const']}');
  }
  if (schema['enum'] case final List<Object?> options
      when !options.contains(value)) {
    errors.add('$path: $value not in $options');
  }
  if (value is Map) {
    for (final key in (schema['required'] as List<Object?>? ?? const [])) {
      if (!value.containsKey(key)) errors.add('$path: missing "$key"');
    }
    final properties =
        schema['properties'] as Map<String, Object?>? ?? const {};
    for (final MapEntry(:key, value: child) in value.entries) {
      final childSchema = properties[key] ?? schema['additionalProperties'];
      if (childSchema is Map<String, Object?>) {
        errors.addAll(violations(child, childSchema, '$path.$key'));
      }
    }
    for (final rule
        in (schema['allOf'] as List<Object?>? ?? const [])
            .cast<Map<String, Object?>>()) {
      if (violations(
        value,
        rule['if']! as Map<String, Object?>,
        path,
      ).isEmpty) {
        errors.addAll(
          violations(value, rule['then']! as Map<String, Object?>, path),
        );
      }
    }
  }
  if (value is List && schema['items'] is Map<String, Object?>) {
    for (var i = 0; i < value.length; i++) {
      errors.addAll(
        violations(
          value[i],
          schema['items']! as Map<String, Object?>,
          '$path[$i]',
        ),
      );
    }
  }
  return errors;
}

void main() {
  final schema = jsonDecode(
    File('../../benchmarks/results/run-record.schema.json').readAsStringSync(),
  ) as Map<String, Object?>;
  Map<String, Object?> example(String name) =>
      jsonDecode(File('examples/$name').readAsStringSync())
          as Map<String, Object?>;
  final load = ModelLoad(
    requestedBackend: 'gpu',
    activeBackend: 'gpu',
    loadTime: const Duration(milliseconds: 1234),
    before: reading(anonymous: 1, maxRss: 2),
    after: reading(anonymous: 3, maxRss: 4),
  );
  final started = DateTime.utc(2026, 10, 31, 8, 15);

  Map<String, Object?> roundTrip(Map<String, Object?> record) =>
      jsonDecode(jsonEncode(record)) as Map<String, Object?>;

  test(
    'an LLM run record matches benchmarks/results/run-record.schema.json',
    () async {
      final clock = FakeClock();
      final runs = await runPromptSet(
        engine: FakeEngine(clock),
        promptSet: const PromptSet(
          version: 'v',
          cases: [PromptCase(id: 'a', maxOutputTokens: 8, prompt: 'p')],
        ),
        repetitions: 1,
        warmupRuns: 0,
        probe: FakeProbe([reading()]),
        memorySampleInterval: null,
        now: clock.call,
      );
      final record = roundTrip(
        llmRunRecord(
          config: SpikeConfig.fromJson(
            example('llm-gemma4-e2b-gpu-timing.json'),
          ) as LlmConfig,
          runId: runIdFor(started, 'llm'),
          startedAt: started,
          finishedAt: started,
          load: load,
          promptSetVersion: 'v',
          runs: runs,
        ),
      );

      expect(violations(record, schema), isEmpty);
      expect(record['runId'], '20261031T081500Z-llm');
    },
  );

  test('an ASR run record matches the schema, and a record missing its results does not', () {
    final record = roundTrip(
      asrRunRecord(
        config: SpikeConfig.fromJson(
          example('asr-whisper-base-timing.json'),
        ) as AsrConfig,
        runId: runIdFor(started, 'asr'),
        startedAt: started,
        finishedAt: started,
        load: load,
        results: const [],
      ),
    );

    expect(violations(record, schema), isEmpty);
    expect(violations(record..remove('results'), schema), [
      '\$: missing "results"',
    ]);
  });

  test('records the package versions that pubspec.lock resolved', () {
    final lock = File('pubspec.lock').readAsStringSync();
    for (final MapEntry(:key, :value) in edgeAiPackageVersions.entries) {
      expect(
        lock,
        matches(
          RegExp(
            '\\n  $key:\\n(?:    .*\\n)*?    version: "${RegExp.escape(value)}"',
          ),
        ),
        reason: key,
      );
    }
  });
}
