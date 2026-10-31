# ADR 0001: Decision gates for the Milestone 0 spike

- Status: proposed. Every threshold below is **proposed, user to confirm**.
- Date: 2026-10-31

## Context

Milestone 1 builds the product around a set of models and languages. Picking them before measuring risks building on a model that is too slow, too large, or too inaccurate on the OnePlus 11R. The spike (`apps/spike`, `benchmarks/evaluation`) produces the numbers. This ADR fixes, before any measurement, which numbers decide what, so the decision can't drift to fit the results.

No threshold here comes from a measurement or a published source. They are starting points for discussion. Replace each one with your own value before you fill in the go/no-go table, and record the confirmed value in this file.

## Decision

Every language and every model gets one of three outcomes:

- **Go on-device.** It passes every gate on the OnePlus 11R. Milestone 1 runs it on the phone.
- **Mac only.** It fails a phone gate but passes on the MacBook Air M4. Milestone 1 can offer it only when the Mac is reachable. The app still has to work without the Mac, so this outcome never replaces an on-device result for the same task.
- **Not viable on-device.** It fails on the phone. The go/no-go table lists its measured numbers next to the verdict.

### Gates for speech recognition, per language

Languages: `en`, `ta`, `ml`, `hi`, `ta-en`, `ml-en`, `hi-en`. Each gate is evaluated per language and per engine (Whisper LiteRT, Gemma 4 E2B audio input).

| Gate | Metric | Proposed threshold (user to confirm) | Why this metric |
| --- | --- | --- | --- |
| A1 accuracy | WER for `en` and `hi`; CER for `ta` and `ml`; both reported for code-switched pairs | `en` WER ≤ 15%, `hi` WER ≤ 25%, `ta` CER ≤ 15%, `ml` CER ≤ 15%, code-switched WER ≤ 35% | Tamil and Malayalam attach suffixes to word stems, so one wrong suffix makes the whole word an error. CER changes less with word length. Both numbers are recorded either way. |
| A2 speed | Real-time factor on the phone (processing time divided by audio duration) | ≤ 0.5, so a 60-minute recording transcribes in 30 minutes or less | Transcription runs after the meeting, but the user wants the notes the same day. |
| A3 memory | Peak OS memory (`dumpsys meminfo` TOTAL PSS) during the run | ≤ 4 GiB | Leaves room for Gemma 4 E2B to run after transcription without the two models sharing memory. |
| A4 stability | Every file in the set finishes, and the app is not killed | No failures | A crash or kill by the low-memory killer is disqualifying, whatever the numbers say. |

The scripted recordings are the primary test set, because they are meetings and visits in the user's own voice and accent, which is how the product will be used. Public datasets (see `benchmarks/datasets/SOURCES.md`) are a cross-check. They can't be used until their licenses are read.

### Gates for summary extraction (Gemma 4 E2B)

| Gate | Metric | Proposed threshold (user to confirm) | Why |
| --- | --- | --- | --- |
| L1 latency | Median end-to-end latency for `en-long` on the phone | ≤ 120 s | Summaries are a background job after transcription. Time to first token matters less than total time. |
| L2 valid output | Share of non-warmup outputs that are valid `MeetingSummary` JSON (`pnpm --filter @fieldnote/contracts validate-outputs`) | ≥ 90% per case | An invalid output is the trigger for escalating to the Mac in Milestone 1. If most outputs fail, the phone path is not useful on its own. |
| L3 memory | Peak OS memory (`dumpsys meminfo` TOTAL PSS) during the run | ≤ 6 GiB | 16 GB of physical RAM, shared with Android and other apps. The 12 GB storage-backed "RAM extension" does not count. |
| L4 thermal | Thermal status during a full repetition set | Never reaches `SEVERE` (`dumpsys thermalservice` status 3) | At `SEVERE` and above, Android throttles hard, and later numbers stop being comparable. |
| L5 stability | Every run finishes, and the app is not killed | No failures | Same as A4. |

Summary quality (are the right action items extracted?) is not a gate for Milestone 0. The prompt set uses fictional transcripts with no reference summaries. Building a scored extraction set is Milestone 1 work.

### Rules for applying the gates

1. Use medians of the non-warmup repetitions for latency, and the maximum over all runs for memory.
2. Measure timing and memory in separate runs. Timing runs use `memorySampleIntervalMs: 0`. Memory runs use `1000` and the `dumpsys meminfo` loop. The memory reads cost CPU and would inflate the timings.
3. A gate that has no measurement is "not yet measured". It is never treated as passed.
4. Report every result, including failures, in `benchmarks/results/`. A language marked "not viable on-device" keeps its numbers.

## Consequences

- Milestone 1 does not start until every row of the go/no-go table in `docs/spike/RUNBOOK.md` has a decision.
- If Whisper fails A1 for Tamil or Malayalam, the next step is a conversion spike for IndicConformer or IndicWhisper ([findings](../spike/findings.md#candidates-that-need-conversion)), not lowering the threshold after seeing the numbers.
- Changing a threshold after measuring is allowed only with a new dated entry in this file that says why.
