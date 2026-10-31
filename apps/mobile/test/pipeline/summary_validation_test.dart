import 'dart:convert';
import 'dart:io';

import 'package:fieldnote_mobile/src/pipeline/summary_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final schema = File('assets/meeting-summary.schema.json').readAsStringSync();
  final validator = SummaryValidator(schema);
  final valid = File(
    '../../packages/contracts/fixtures/meeting-summary.valid.json',
  ).readAsStringSync();

  test(
    'the bundled schema and prompt are the contracts files, byte for byte',
    () {
      expect(
        schema,
        File('../../packages/contracts/schema/meeting-summary.schema.json')
            .readAsStringSync(),
      );
      expect(
        File('assets/summarize-prompt.txt').readAsStringSync(),
        File('../../packages/contracts/prompts/summarize.txt')
            .readAsStringSync(),
      );
    },
  );

  test('accepts the valid fixture, bare or in one code fence', () {
    expect(validator.validate(valid), isA<ValidSummary>());
    expect(
      validator.validate('```json\n${valid.trim()}\n```'),
      isA<ValidSummary>(),
    );
  });

  test(
    'rejects prose, non-JSON, and every invalid fixture the gateway rejects',
    () {
      expect(validator.validate('Here you go:\n$valid'), isA<InvalidSummary>());
      expect(
        (validator.validate('nope') as InvalidSummary).reason,
        'the answer is not JSON',
      );
      final invalid = jsonDecode(
        File('../../packages/contracts/fixtures/meeting-summary.invalid.json')
            .readAsStringSync(),
      ) as List<Object?>;
      for (final candidate in invalid) {
        expect(
          validator.validate(jsonEncode(candidate)),
          isA<InvalidSummary>(),
          reason: jsonEncode(candidate),
        );
      }
    },
  );

  test(
    'fills the prompt with the transcript and the pretty-printed schema',
    () {
      final prompt = summarizePrompt(
        template: File('assets/summarize-prompt.txt').readAsStringSync(),
        schemaJson: schema,
        transcript: 'Arun: hello',
      );
      expect(prompt, contains('Arun: hello'));
      expect(prompt, contains('"title": "MeetingSummary"'));
      expect(prompt, isNot(contains('{schema}')));
    },
  );
}
