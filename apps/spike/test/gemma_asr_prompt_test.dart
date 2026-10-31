import 'dart:convert';
import 'dart:io';

import 'package:fieldnote_spike/src/gemma_asr_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fills the language name into the model card prompt', () {
    final prompt = gemmaAsrPrompt('Tamil and English');

    expect(
      prompt,
      startsWith(
        'Transcribe the following speech segment in Tamil and English into Tamil and English text.',
      ),
    );
    expect(prompt, contains('Only output the transcription'));
  });

  test('rejects a language code, because the prompt needs a name', () {
    expect(() => gemmaAsrPrompt('ta'), throwsArgumentError);
  });

  test('the Gemma example config gives a language name for every language', () {
    final config = jsonDecode(
      File('examples/asr-gemma4-audio-timing.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final names =
        ((config['asr']! as Map<String, Object?>)['decodeLanguage']!
                as Map<String, Object?>)
            .values;

    for (final name in names) {
      expect(
        () => gemmaAsrPrompt(name! as String),
        returnsNormally,
        reason: '$name',
      );
    }
  });
}
