# Architecture

Fieldnote records a meeting or customer visit on the phone, transcribes it, and extracts a structured summary (participants, topics, decisions, action items with owners and deadlines). The phone does all of this by itself. When a job is too large for the phone, or the phone's output fails validation, the app can send the job to a larger model on the user's Mac over the local network. The app has to stay useful when the Mac is off.

Status: only the boxes marked **built** exist. Everything else is planned. [PROGRESS.md](../PROGRESS.md) tracks status.

```mermaid
flowchart LR
  subgraph phone["Phone: Flutter app (apps/mobile)"]
    rec["Recorder<br/>(planned)"]
    asr["On-device ASR<br/>flutter_edge_ai_speech<br/>(planned)"]
    llm["On-device extraction<br/>Gemma 4 E2B<br/>(planned)"]
    val["Validate against<br/>MeetingSummary schema<br/>(planned)"]
    route["Routing policy, Dart<br/>deterministic<br/>(built, not wired)"]
    jobs[("Durable job store<br/>(built, not wired)")]
    rec --> jobs
    jobs --> route
    route -->|on device| asr --> llm --> val
    val -->|valid| jobs
    val -->|invalid or too large| route
  end

  subgraph mac["Mac: gateway (services/gateway)"]
    health["GET /health<br/>(built)"]
    api["Job API, SQLite<br/>(built, no model yet)"]
    big["Gemma 4 12B candidate<br/>(planned, not measured)"]
    api --> big
  end

  route -->|"escalate when paired and reachable<br/>(planned)"| api
  api -->|result| jobs

  contracts["packages/contracts<br/>JSON Schema, generated Dart and TS<br/>(built)"]
  contracts -.-> phone
  contracts -.-> mac
```

## Components

### Phone app (`apps/mobile`)

The phone app is built with Flutter for Android and macOS. iOS is out of scope, because the project has no iOS device. Today it shows one placeholder screen. In Milestone 1 it will own recording, the job store, on-device ASR and extraction, validation, and the routing policy.

### Routing policy (planned, in the app)

The routing policy (`apps/mobile/lib/src/routing/routing_policy.dart`) is a Dart function of the task type, the input size, the validation result, whether the Mac is paired and reachable, and the user's settings. It is deterministic. Historical accuracy is not an input. The gateway never makes routing decisions. See [ADR 0002](decisions/0002-routing-in-the-app.md).

### Gateway (`services/gateway`)

The gateway is a Fastify and TypeScript service on the Mac. It serves `GET /health` and an idempotent job API backed by SQLite ([ADR 0008](decisions/0008-gateway-job-api.md)), validates its environment at startup, and writes structured JSON logs with a correlation ID per request. No model runs on it yet. It listens only on loopback until pairing exists ([ADR 0006](decisions/0006-gateway-binds-loopback-until-pairing.md)).

### Contracts (`packages/contracts`)

The contracts package holds JSON Schema files, with TypeScript and Dart types that quicktype generates from them. CI fails if the generated files are stale. See [ADR 0003](decisions/0003-contracts-generator.md).

### Spike and evaluation (`apps/spike`, `benchmarks/`)

These are the Milestone 0 measurement tools. The spike app measures on-device LLM and ASR latency and memory. `benchmarks/evaluation` computes WER and CER and summarizes run files. Their results decide which models and languages go into Milestone 1 ([ADR 0001](decisions/0001-spike-decision-gates.md)).

## Execution modes that the evaluation compares

| Mode | ASR | Extraction | Needs the Mac |
| --- | --- | --- | --- |
| Phone only | phone | phone | no |
| Mac only | Mac | Mac | yes |
| Hybrid | phone | phone, escalating to the Mac when validation fails or the input is too large | only for escalated jobs |

Only phone-only measurements are possible in Milestone 0, because the gateway has no inference yet.
