# ADR 0008: Gateway job API, storage and failure semantics

- Status: accepted
- Date: 2026-11-01

## Context

The phone escalates a summarize job to the Mac when its own output fails validation or the input is too large ([ADR 0007](0007-job-store-and-routing-rules.md)). The Mac model is not chosen yet: Gemma 4 12B is the candidate, and its fit on the 16 GB MacBook Air is not yet measured. The API and its failure handling can be built and tested now with a scripted backend.

## Decision

### Endpoints

| Method and path | Success | Errors |
| --- | --- | --- |
| `POST /v1/jobs` with a `JobSubmission` | 202 `JobStatus` for a new or requeued job. 200 `JobStatus` when the same body was already submitted. | 400 if the body breaks the schema. 409 if the job ID exists with a different body. 503 if no inference backend is configured. |
| `GET /v1/jobs/:jobId` | 200 `JobStatus` | 404 |
| `GET /v1/jobs/:jobId/summary` | 200 `MeetingSummary` | 404, or 409 if the job is not completed |

Only `summarize` jobs exist. Transcription on the Mac needs audio upload, which waits until the go/no-go table shows whether phone transcription is enough.

The summary is a separate endpoint instead of a field of `JobStatus`. With a nullable `$ref` inside `JobStatus`, quicktype generated a second copy of `MeetingSummary` under another name, which is the drift that [ADR 0003](0003-contracts-generator.md) exists to prevent.

### Idempotency and failure kinds

- A job is identified by the phone's job ID. The gateway stores a SHA-256 hash of the kind, transcript and language. The same body again returns the stored job and does not run the model.
- A failed job carries an error kind. `invalid_output` means the model answered but the answer is not a valid `MeetingSummary`. A resubmit returns the failed job unchanged. The Mac backend is to decode greedily, like the spike, and a greedy rerun of the same prompt gives the same answer. `backend_error` means the model could not answer, such as the model server being down. A resubmit queues the job again and counts the attempt. The phone owns the retry schedule ([`RetryPolicy`](../../apps/mobile/lib/src/jobs/job.dart)), so the gateway never retries by itself.
- The gateway validates every answer against the `MeetingSummary` schema with Ajv before a job is `completed`. One Markdown code fence around the whole answer is accepted.

### Storage

- Jobs live in SQLite through Node's built-in `node:sqlite` module, at `$DATA_DIR/gateway.sqlite` (default `./data`). Each state change is one statement or one `BEGIN IMMEDIATE` transaction. On startup, jobs left in `processing` go back to `queued`.
- `node:sqlite` is marked experimental in Node 22 and prints an `ExperimentalWarning` at startup. It was chosen over `better-sqlite3` because it needs no native build and no new dependency. The gateway uses only `DatabaseSync`, `prepare`, `run`, `get` and `exec`. If a Node upgrade changes that API, the change is confined to `services/gateway/src/jobs/store.ts`.

### Inference backend

`InferenceBackend` is one method, `generate(prompt): Promise<string>`. A real backend must decode greedily (top-k 1), so that `invalid_output` stays final. `INFERENCE_BACKEND` accepts only `none` today, so a running gateway answers 503 to new jobs instead of accepting work it can't do. Tests use a scripted backend. A real backend is added once the Mac model is measured.

The prompt is `packages/contracts/prompts/summarize.txt`, the same template the spike measures on the phone. A spike test fails if the two drift apart.

## Consequences

- The phone can be built against the real API, including its failure kinds, before a model runs on the Mac.
- There is still no authentication. The gateway listens on loopback only ([ADR 0006](0006-gateway-binds-loopback-until-pairing.md)) until pairing and TLS exist.
