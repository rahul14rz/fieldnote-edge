import 'dart:convert';

import 'package:fieldnote_contracts/fieldnote_contracts.dart';
import 'package:json_schema/json_schema.dart';

sealed class Validation {
  const Validation();
}

class ValidSummary extends Validation {
  const ValidSummary(this.summary, this.json);
  final MeetingSummary summary;

  /// The exact JSON text to store.
  final String json;
}

class InvalidSummary extends Validation {
  const InvalidSummary(this.reason);
  final String reason;
}

/// Checks a model answer against the MeetingSummary JSON Schema, the same
/// rule the gateway applies (services/gateway/src/jobs/worker.ts): one
/// Markdown code fence around the whole answer is accepted, any other text
/// makes the answer invalid.
class SummaryValidator {
  SummaryValidator(String schemaJson)
    : _schema = JsonSchema.create(jsonDecode(schemaJson) as Object);

  final JsonSchema _schema;
  static final _fence = RegExp(r'^\s*```(?:json)?\s*\n([\s\S]*?)\n```\s*$');

  Validation validate(String answer) {
    final fenced = _fence.firstMatch(answer);
    final Object? value;
    try {
      value = jsonDecode(fenced?.group(1) ?? answer);
    } on FormatException {
      return const InvalidSummary('the answer is not JSON');
    }
    final result = _schema.validate(value);
    if (!result.isValid) {
      return InvalidSummary(
        'the answer is not a valid MeetingSummary: ${result.errors.map((e) => '${e.instancePath} ${e.message}').join('; ')}',
      );
    }
    final map = value! as Map<String, dynamic>;
    return ValidSummary(MeetingSummary.fromJson(map), jsonEncode(map));
  }
}

/// Fills the shared summarize prompt (packages/contracts/prompts/summarize.txt).
String summarizePrompt({
  required String template,
  required String schemaJson,
  required String transcript,
}) => template
    .replaceFirst(
      '{schema}',
      const JsonEncoder.withIndent('  ').convert(jsonDecode(schemaJson)),
    )
    .replaceFirst('{transcript}', transcript);
