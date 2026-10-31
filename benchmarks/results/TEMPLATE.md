# Results: <round name, for example 2026-11 baseline>

Copy this file to `benchmarks/results/<date>-<round>.md` and fill it in from your runs. Every cell starts as "not yet measured". Replace a cell only with a number from a result file or from a tool output you recorded. Put the matching `summary.json` (shape: [`results.schema.json`](results.schema.json)) next to the copy.

- Devices: see [`docs/devices.md`](../../docs/devices.md).
- How to produce each number: [`docs/spike/RUNBOOK.md`](../../docs/spike/RUNBOOK.md).
- Medians are over repetitions, excluding warmup runs. Peaks are the maximum over all runs.

## Run metadata

| Field | Value |
| --- | --- |
| Date | not yet measured |
| Git commit of `apps/spike` | not yet measured |
| flutter_edge_ai package versions (from a result file's `packages`) | not yet measured |
| Prompt set version | not yet measured |
| Phone: Android build number, battery level, charging or not | not yet measured |
| Mac: macOS version, on battery or on power | not yet measured |

## LLM: Gemma 4 E2B

One row per device, backend and prompt case. "Active backend" is what the engine reported it loaded.

| Device | Requested backend | Active backend | Case | Runs | Median load (ms) | Median TTFT (ms) | Median decode (tokens/s) | Median end-to-end (ms) | Peak anonymous (MiB) | Peak file-backed (MiB) | Peak RSS (MiB) | OS peak memory (MiB) | Thermal before | Thermal after |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| OnePlus 11R | gpu | not yet measured | en-short | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured |
| OnePlus 11R | gpu | not yet measured | en-medium | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured |
| OnePlus 11R | gpu | not yet measured | en-long | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured |
| OnePlus 11R | gpu | not yet measured | hi-en-short | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured |
| OnePlus 11R | gpu | not yet measured | ta-en-short | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured |
| OnePlus 11R | gpu | not yet measured | ml-en-short | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured |
| OnePlus 11R | cpu | not yet measured | en-long | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured |
| MacBook Air M4 | gpu | not yet measured | en-short | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured |
| MacBook Air M4 | gpu | not yet measured | en-long | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured |
| MacBook Air M4 | cpu | not yet measured | en-long | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured |

The file-backed column is empty on macOS, because `flutter_edge_ai_diagnostics` does not report that field there.

## ASR

One row per device, engine and language. WER and CER come from `python3 -m asr_eval` with normalizer `fieldnote-v1`. RTF is processing time divided by audio duration, so a value below 1 is faster than real time.

| Device | Engine and model | Language | Files | Audio (s) | WER | CER | RTF | Peak anonymous (MiB) | Peak RSS (MiB) | Thermal before | Thermal after |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| OnePlus 11R | whisper, whisper-base-30s-i8 | en | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured |
| OnePlus 11R | whisper, whisper-base-30s-i8 | ta | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured |
| OnePlus 11R | whisper, whisper-base-30s-i8 | ml | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured |
| OnePlus 11R | whisper, whisper-base-30s-i8 | hi | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured |
| OnePlus 11R | whisper, whisper-base-30s-i8 | ta-en | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured |
| OnePlus 11R | whisper, whisper-base-30s-i8 | ml-en | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured |
| OnePlus 11R | whisper, whisper-base-30s-i8 | hi-en | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured |
| OnePlus 11R | gemmaAudio, gemma-4-E2B-it | en | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured |
| OnePlus 11R | gemmaAudio, gemma-4-E2B-it | ta | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured |
| OnePlus 11R | gemmaAudio, gemma-4-E2B-it | ml | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured |
| OnePlus 11R | gemmaAudio, gemma-4-E2B-it | hi | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured |
| OnePlus 11R | gemmaAudio, gemma-4-E2B-it | ta-en | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured |
| OnePlus 11R | gemmaAudio, gemma-4-E2B-it | ml-en | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured |
| OnePlus 11R | gemmaAudio, gemma-4-E2B-it | hi-en | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured |

Add MacBook Air M4 rows in the same shape if you run ASR on the Mac.

## Go/no-go

Fill in the go/no-go table in [`docs/spike/RUNBOOK.md`](../../docs/spike/RUNBOOK.md#fill-in-the-gono-go-table), and copy the completed table here.
