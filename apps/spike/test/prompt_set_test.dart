import 'dart:convert';
import 'dart:io';

import 'package:fieldnote_spike/src/prompt_set.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final schema = File('assets/meeting-summary.schema.json').readAsStringSync();
  final promptSet = PromptSet.fromJson(
    jsonDecode(File('assets/prompt_set.json').readAsStringSync())
        as Map<String, Object?>,
    schema: schema,
  );

  test('the bundled schema is the contracts schema, byte for byte', () {
    expect(
      schema,
      File('../../packages/contracts/schema/meeting-summary.schema.json')
          .readAsStringSync(),
    );
  });

  test('covers English at three lengths and each code-switched pair', () {
    expect(
      promptSet.cases.map((c) => c.id),
      containsAll([
        'en-short',
        'en-medium',
        'en-long',
        'hi-en-short',
        'ta-en-short',
        'ml-en-short',
      ]),
    );
  });

  test('every prompt embeds the schema and a transcript, and longer cases contain more transcript', () {
    for (final c in promptSet.cases) {
      expect(c.prompt, contains(schema), reason: c.id);
      expect(c.prompt, contains('Transcript:\n'), reason: c.id);
    }
    int length(String id) =>
        promptSet.cases.firstWhere((c) => c.id == id).prompt.length;
    expect(length('en-short'), lessThan(length('en-medium')));
    expect(length('en-medium'), lessThan(length('en-long')));
  });

  test('rejects a case that names a transcript part that does not exist', () {
    expect(
      () => PromptSet.fromJson({
        'version': 'x',
        'template': '{schema} {transcript}',
        'transcripts': <String, Object?>{},
        'cases': [
          {
            'id': 'a',
            'maxOutputTokens': 1,
            'transcriptParts': ['missing'],
          },
        ],
      }, schema: '{}'),
      throwsFormatException,
    );
  });
}
