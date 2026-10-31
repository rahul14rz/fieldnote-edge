# Spike app

This is the Milestone 0 measurement app. It runs one configured measurement and writes a JSON result file that follows [`benchmarks/results/run-record.schema.json`](../../benchmarks/results/run-record.schema.json). [`docs/spike/RUNBOOK.md`](../../docs/spike/RUNBOOK.md) has the device steps.

It has two modes:

- **`llm`.** Loads a `.litertlm` model and runs the fixed prompt set in `assets/prompt_set.json` (fictional, scripted transcripts). For every run it records prompt tokens, time to first token, end-to-end latency, decode tokens per second, and memory.
- **`asr`.** Transcribes 16 kHz mono WAV files listed in a manifest, with Whisper (`flutter_edge_ai_speech`) or with Gemma 4 audio input. Audio is split into 30-second windows, because the speech package truncates longer audio without an error. It writes `results/<runId>.hypotheses.jsonl` for `benchmarks/evaluation`.

Example configs are in `examples/`. Copy one into the work directory as `spike_config.json`.

## Definitions

- **Time to first token.** From submitting the prompt to the first non-empty streamed chunk. This includes prefill.
- **End-to-end latency.** From submitting the prompt to the end of the response stream.
- **Decode tokens per second.** (output tokens − 1) divided by the time between the first and last chunk. The app counts output tokens after generation with the model's tokenizer (`sizeInTokens`), because one streamed chunk is not guaranteed to be one token.
- **Memory.** The `flutter_edge_ai_diagnostics` snapshot fields (`anonymousBytes`, `fileBackedBytes`, and `anonymousPeakBytes` on macOS), plus `ProcessInfo.maxRss`. With `memorySampleIntervalMs: 0`, the app reads memory only before and after each prompt or file. Use that setting for timing runs, because each Android snapshot reads `/proc`.

Generation uses `topK: 1` (greedy decoding), so every repetition of a prompt produces the same output and its timings are comparable.

## Checks

```bash
cd apps/spike
flutter pub get
flutter analyze
flutter test
```

The tests use fake engines. They check the metric definitions, WAV handling, windowing, configs, the prompt set, and the run-record schema. They do not load a model.
