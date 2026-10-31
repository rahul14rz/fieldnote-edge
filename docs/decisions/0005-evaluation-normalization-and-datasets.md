# ADR 0005: ASR text normalization and evaluation data

- Status: accepted
- Date: 2026-10-31

## Context

WER and CER depend on how reference and hypothesis text are normalized before comparison. The common English-centric normalizer gives wrong results for the Indic scripts this project needs. The published evaluation also needs data that the project is allowed to publish.

## Decision

### Normalization (`fieldnote-v1`)

`benchmarks/evaluation/asr_eval/normalize.py` applies Unicode NFC and `casefold()`, removes zero-width characters, replaces punctuation, symbols and separators with a space, and collapses whitespace. It keeps every combining mark (Unicode category M*).

Whisper's `BasicTextNormalizer` replaces every M* character with a space, and with `remove_diacritics=True` it deletes every Mn character after NFKD ([`whisper/normalizers/basic.py`](https://github.com/openai/whisper/blob/86098128c0b4f24f0e2aa2994de830614b474227/whisper/normalizers/basic.py#L27-L56)). In Tamil, Malayalam and Hindi, those characters are vowel signs (matras), viramas and anusvaras. Removing them turns காலை into `க ல` and hides real recognition errors. The `MatraPreservation` tests fail if either Whisper behavior is reintroduced. Both variants were tried against the tests. Replacing M* with a space fails 6 tests, and deleting Mn after NFKD fails 5.

Other choices, picked as the simplest option and open to change in a new normalizer version:

- Zero-width joiners and non-joiners are removed. They change rendering, not the word, in the texts this project expects. A model that drops one is not penalized.
- Numbers are not normalized. "5" and "five" differ.
- CER counts Unicode code points, including the single spaces between words. Grapheme clusters would need a third-party package, and the evaluator uses only the standard library.
- Rates are pooled per language: total edits over total reference words or characters.

Any change to these rules gets a new normalizer ID. Reports carry the ID, and results with different IDs are not compared.

### Evaluation data

- The published evaluation contains no real client meetings or visits.
- Meeting-style audio comes from scripted recordings the user makes, with written consent from every speaker before anything is published.
- Public speech datasets are used only for ASR error rates, and only after their license is read and recorded in `benchmarks/datasets/SOURCES.md`. A license that could not be read is marked "unverified", and that dataset is not used until it is checked.
- Raw audio and device result files stay out of git (`benchmarks/datasets/local/`, `benchmarks/results/raw/`).

## Consequences

- Indic WER and CER from this project can't be compared directly with published numbers that used Whisper's normalizer. Reports state the normalizer ID.
- Tamil-English and Malayalam-English evaluation depends on the user's scripted recordings until a public code-switched dataset with a readable license is found.
