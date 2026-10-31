# ASR evaluation

`asr_eval` computes word error rate (WER) and character error rate (CER) per language. It needs only the Python standard library (Python 3.11 or later).

## Run it

```bash
cd benchmarks/evaluation
python3 -m asr_eval --references examples/references.jsonl --hypotheses examples/hypotheses.jsonl --output report.json
```

The command writes the report to `--output` and also prints it. If a reference has no matching hypothesis, or uses a language code not in the list below, the command exits with code 2 and writes nothing.

## Input format

Both files are JSON Lines, one utterance per line.

- References: `{"id": "...", "language": "ta", "text": "..."}`
- Hypotheses: `{"id": "...", "text": "..."}`

Language codes: `en`, `ta`, `ml`, `hi`, `ta-en`, `ml-en`, `hi-en`. The last three are code-switched speech.

The files in `examples/` only show the format. They contain no measurements.

## How text is normalized

The normalizer ID is `fieldnote-v1` and it appears in every report. Results produced with different normalizers can't be compared.

1. Apply Unicode NFC, so canonically equivalent spellings compare as equal.
2. Apply `casefold()`. This affects Latin text only.
3. Remove zero-width characters (U+200B, U+200C, U+200D, U+2060, U+FEFF).
4. Replace punctuation (P\*), symbols (S\*) and separators (Z\*) with a space.
5. Collapse runs of whitespace.

Combining marks (M\*) are kept. In Tamil, Malayalam and Hindi, these marks are vowel signs (matras), viramas and anusvaras, and they are part of the word. Whisper's `BasicTextNormalizer` replaces every M\* character with a space. With `remove_diacritics=True`, it drops every Mn character after NFKD instead. See [`whisper/normalizers/basic.py`](https://github.com/openai/whisper/blob/86098128c0b4f24f0e2aa2994de830614b474227/whisper/normalizers/basic.py#L27-L56). Either way, a word such as காலை becomes `க ல`, and recognition errors in the vowel signs disappear from the score.

Numbers are compared exactly as written: "5" and "five" count as different words. CER counts Unicode code points, including the single spaces between words, so one missing vowel sign counts as one character error.

## Rates

WER and CER are pooled per language. Each rate is the total number of edits divided by the total number of reference words or characters. Each utterance therefore counts in proportion to its length, not equally.

## Summarize spike result files

`summarize_runs.py` reads result files written by `apps/spike` and produces the measured rows of `benchmarks/results/TEMPLATE.md` (shape: `benchmarks/results/results.schema.json`). Latency is the median of non-warmup runs. Memory is the maximum over runs.

```bash
cd benchmarks/evaluation
python3 summarize_runs.py --output summary.json ../results/raw/*/*.json
```

## Tests

```bash
cd benchmarks/evaluation
python3 -m unittest discover -s tests -t .
```

`tests/test_normalize.py` has a `MatraPreservation` group. It fails if the normalizer drops or splits on vowel signs or viramas. Both of Whisper's variants were tried against it: replacing M\* with a space fails 6 tests, and deleting Mn after NFKD fails 5.
