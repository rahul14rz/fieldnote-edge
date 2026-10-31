import 'dart:convert';
import 'dart:io';

import 'package:fieldnote_contracts/fieldnote_contracts.dart';
import 'package:test/test.dart';

void main() {
  test('parses the shared valid fixture, keeping nulls the schema allows', () {
    final json = File('../fixtures/meeting-summary.valid.json')
        .readAsStringSync();

    final summary = meetingSummaryFromJson(json);

    expect(summary.participants.map((p) => p.name), ['Priya', 'Arun']);
    expect(summary.participants[1].role, isNull);
    expect(summary.actionItems[0].owner, 'Arun');
    expect(summary.actionItems[0].dueDate, '2026-11-06');
    expect(summary.actionItems[1].owner, isNull);
    expect(summary.actionItems[1].dueDate, isNull);
  });

  test(
    'serializes back to exactly the fixture, so Dart output stays schema-valid',
    () {
      final json = File('../fixtures/meeting-summary.valid.json')
          .readAsStringSync();

      expect(meetingSummaryFromJson(json).toJson(), jsonDecode(json));
    },
  );
}
