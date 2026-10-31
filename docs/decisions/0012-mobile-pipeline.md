# ADR 0012: The mobile job pipeline

- Status: accepted
- Date: 2026-11-01

## Context

The phone records a meeting, transcribes it, and extracts a summary. The job store ([ADR 0007](0007-job-store-and-routing-rules.md)), the routing policy and the gateway client exist. This ADR records how they are wired together in `apps/mobile`.

## Decision

### Flow

1. The user picks the meeting language and records. The app writes 16 kHz mono 16-bit WAV with `record`, the only format `flutter_edge_ai_speech` reads.
2. Stopping adds a `transcribe` job. The job runner (`lib/src/pipeline/job_runner.dart`) takes the next runnable job, asks `route()` where it goes, and runs it.
3. Transcription runs only on the phone: Whisper base through `flutter_edge_ai_speech`, 30 seconds at a time. The gateway accepts summary jobs only ([ADR 0008](0008-gateway-job-api.md)), so the runner routes transcription as if no Mac were paired. A finished transcription adds a `summarize` job with the ID `<recording>.summary`.
4. Summary extraction runs on the phone first: Gemma 4 E2B, greedy, with the shared prompt. The answer is validated against the `MeetingSummary` schema with `json_schema`, by the same rule as the gateway.
5. An invalid or failed phone answer moves the job to `retryable` with no delay and records the phone outcome. On the next run, routing sends it to the Mac if the Mac is paired, allowed and online. It waits if the paired Mac is offline, and it fails with the reason otherwise.
6. On the Mac, the runner submits the job, polls every 2 seconds for up to 15 minutes, and validates the summary again before storing it.

### Job state changes added

- `queued` to `retryable` (`waitForMac`): routing chose to wait for the paired Mac. It is not an attempt, so it does not count toward the retry limit.
- `queued` to `failed`: routing found nowhere to run the job, for example no speech model.
- `processing` to `retryable` with no delay (`escalate`): the phone result can't be used, and routing decides the next step.

### Failure handling

| Failure | Result |
| --- | --- |
| Audio is not 16 kHz mono 16-bit PCM | `failed`, because a retry reads the same file |
| The speech engine throws | `retryable` with backoff |
| The phone summary is invalid, or the phone model throws | Escalate as above |
| The Mac is unreachable or times out | `retryable` with backoff |
| The Mac summary is invalid too | `failed`, so the job doesn't loop between the phone and the Mac |

### Models, size input and storage

- `lib/src/platform/model_catalog.dart` names the models to download: Gemma 4 E2B `.litertlm` and Whisper base int8. These are the spike candidates, not a measured choice. The summary context is 8192 tokens, which is not measured either.
- Routing's size input for summaries is the transcript's **word** count. The phone can't count model tokens before the model loads, so the limit is named `maxPhoneTranscriptWords`. Both limits stay unset until the spike measures them.
- The paired gateway's credential lives in `flutter_secure_storage` (Android Keystore, macOS Keychain). Jobs, settings and recordings live in the app support directory.
- Android needs a Wi-Fi multicast lock for mDNS. `MainActivity.kt` exposes one through the `fieldnote/multicast` channel, and discovery holds it while it browses. The pairing screen also takes an address and port typed by hand, in case discovery finds nothing.

## Consequences

- The app is useful without a Mac. Every summary that the phone produces and that passes validation completes on the phone.
- Model choice, the size limits and the context length are each a one-line change in `model_catalog.dart` or `RoutingThresholds` once the go/no-go table is filled in.
- None of this has run on a device. The tests use fake engines, and `flutter build apk --release --target-platform android-arm64` succeeds.
