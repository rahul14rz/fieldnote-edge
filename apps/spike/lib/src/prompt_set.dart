class PromptCase {
  const PromptCase({
    required this.id,
    required this.maxOutputTokens,
    required this.prompt,
  });

  final String id;
  final int maxOutputTokens;
  final String prompt;
}

/// The fixed prompts every LLM run uses. The version goes into each result
/// so that runs with different prompts are never compared.
class PromptSet {
  const PromptSet({required this.version, required this.cases});

  final String version;
  final List<PromptCase> cases;

  /// [json] is `assets/prompt_set.json`; [schema] is the MeetingSummary JSON
  /// Schema text, embedded in each prompt so the model sees the contract.
  factory PromptSet.fromJson(
    Map<String, Object?> json, {
    required String schema,
  }) {
    final template = json['template'] as String;
    if (!template.contains('{schema}') || !template.contains('{transcript}')) {
      throw const FormatException(
        'template must contain {schema} and {transcript}',
      );
    }
    final transcripts = (json['transcripts'] as Map<String, Object?>)
        .cast<String, String>();
    final cases = [
      for (final raw
          in (json['cases'] as List<Object?>).cast<Map<String, Object?>>())
        PromptCase(
          id: raw['id'] as String,
          maxOutputTokens: raw['maxOutputTokens'] as int,
          prompt: template
              .replaceAll('{schema}', schema)
              .replaceAll(
                '{transcript}',
                (raw['transcriptParts'] as List<Object?>)
                    .map(
                      (part) =>
                          transcripts[part] ??
                          (throw FormatException(
                            'unknown transcript part "$part"',
                          )),
                    )
                    .join('\n'),
              ),
        ),
    ];
    final ids = cases.map((c) => c.id).toSet();
    if (ids.length != cases.length) {
      throw const FormatException('duplicate case ids');
    }
    return PromptSet(version: json['version'] as String, cases: cases);
  }
}
