/// What one spike run measures. Parsed from `spike_config.json` in the work
/// directory, and copied into every result file.
sealed class SpikeConfig {
  SpikeConfig({required this.deviceLabel, required this.raw})
    : memorySampleInterval = switch (raw['memorySampleIntervalMs']) {
        0 => null,
        final int ms when ms >= 1000 => Duration(milliseconds: ms),
        _ => throw const FormatException(
          '"memorySampleIntervalMs" must be 0 (before and after only) or >= 1000',
        ),
      };

  final String deviceLabel;
  final Map<String, Object?> raw;

  /// Null means memory is read only before and after each prompt or file.
  final Duration? memorySampleInterval;

  static SpikeConfig fromJson(Map<String, Object?> json) {
    final deviceLabel = _string(json, 'deviceLabel');
    return switch (_string(json, 'mode')) {
      'llm' => LlmConfig._(deviceLabel, json, _object(json, 'llm')),
      'asr' => AsrConfig._(deviceLabel, json, _object(json, 'asr')),
      final other => throw FormatException(
        'mode must be "llm" or "asr", got "$other"',
      ),
    };
  }
}

enum Backend { cpu, gpu }

class LlmConfig extends SpikeConfig {
  LlmConfig._(
    String deviceLabel,
    Map<String, Object?> raw,
    Map<String, Object?> llm,
  ) : modelId = _string(llm, 'modelId'),
      modelFile = _string(llm, 'modelFile'),
      backend = _enum(llm, 'backend', Backend.values),
      contextTokens = _int(llm, 'contextTokens', min: 1024),
      repetitions = _int(llm, 'repetitions', min: 1),
      warmupRuns = _int(llm, 'warmupRuns', min: 0),
      super(deviceLabel: deviceLabel, raw: raw);

  final String modelId;
  final String modelFile;
  final Backend backend;
  final int contextTokens;
  final int repetitions;
  final int warmupRuns;
}

enum AsrEngine { whisper, gemmaAudio }

class AsrConfig extends SpikeConfig {
  AsrConfig._(
    String deviceLabel,
    Map<String, Object?> raw,
    Map<String, Object?> asr,
  ) : engine = _enum(asr, 'engine', AsrEngine.values),
      modelId = _string(asr, 'modelId'),
      modelFile = _string(asr, 'modelFile'),
      tokenizerFile = asr['tokenizerFile'] as String?,
      backend = _enum(asr, 'backend', Backend.values),
      manifest = _string(asr, 'manifest'),
      windowSeconds = _int(asr, 'windowSeconds', min: 1),
      decodeLanguage = {
        for (final MapEntry(:key, :value) in _object(
          asr,
          'decodeLanguage',
        ).entries)
          key: value is String
              ? value
              : throw FormatException('decodeLanguage.$key must be a string'),
      },
      super(deviceLabel: deviceLabel, raw: raw) {
    if (engine == AsrEngine.whisper && tokenizerFile == null) {
      throw const FormatException(
        'asr.tokenizerFile is required for the whisper engine',
      );
    }
  }

  final AsrEngine engine;
  final String modelId;
  final String modelFile;
  final String? tokenizerFile;
  final Backend backend;

  /// JSON Lines file of `{"id", "language", "audio"}` relative to the work directory.
  final String manifest;
  final int windowSeconds;

  /// Language code passed to the recognizer for each manifest language,
  /// for example `{"ta-en": "ta"}`. Code-switched speech has no single code.
  final Map<String, String> decodeLanguage;
}

String _string(Map<String, Object?> json, String key) => switch (json[key]) {
  final String value when value.isNotEmpty => value,
  _ => throw FormatException('"$key" must be a non-empty string'),
};

int _int(Map<String, Object?> json, String key, {required int min}) =>
    switch (json[key]) {
      final int value when value >= min => value,
      _ => throw FormatException('"$key" must be an integer >= $min'),
    };

Map<String, Object?> _object(Map<String, Object?> json, String key) =>
    switch (json[key]) {
      final Map<String, Object?> value => value,
      _ => throw FormatException('"$key" must be an object'),
    };

T _enum<T extends Enum>(Map<String, Object?> json, String key, List<T> values) {
  final name = json[key];
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw FormatException(
    '"$key" must be one of ${values.map((v) => v.name).join(', ')}, got "$name"',
  );
}
