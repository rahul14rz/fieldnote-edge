# Progress

Last updated: 2026-11-01.

## Milestone 0: feasibility spike

| Item | Status | Where |
| --- | --- | --- |
| Package versions, compatibility and licenses checked | done | [docs/spike/findings.md](docs/spike/findings.md) |
| Model licenses checked | done on 2026-11-01. Gemma 4 E2B and 12B, the Whisper LiteRT files, and community Indic Whisper are Apache 2.0. IndicConformer and IndicWhisper are MIT. | [docs/spike/findings.md](docs/spike/findings.md#model-licenses) |
| Dataset licenses checked | partly done. FLEURS, IndicVoices and Kathbath are CC BY 4.0. Common Voice, Svarah, MUCS 2021 and OpenSLR are unverified. | [benchmarks/datasets/SOURCES.md](benchmarks/datasets/SOURCES.md) |
| Spike app (LLM and ASR timing and memory) | built and unit-tested with fakes. Not run on a device. | [apps/spike](apps/spike) |
| WER and CER evaluator | built and tested, including the matra-preservation tests | [benchmarks/evaluation](benchmarks/evaluation) |
| Results template, schemas, summarizer, output validator | built | [benchmarks/results](benchmarks/results) |
| Runbook | written. Not yet followed on a device. | [docs/spike/RUNBOOK.md](docs/spike/RUNBOOK.md) |
| Decision gates | proposed. Thresholds await the user's confirmation. | [ADR 0001](docs/decisions/0001-spike-decision-gates.md) |
| Scripted recordings | not recorded | [benchmarks/datasets/SOURCES.md](benchmarks/datasets/SOURCES.md) |
| Device measurements on the OnePlus 11R | not yet measured | [docs/spike/RUNBOOK.md](docs/spike/RUNBOOK.md) |
| Device measurements on the MacBook Air M4 | not yet measured | [docs/spike/RUNBOOK.md](docs/spike/RUNBOOK.md) |
| Go/no-go table | not filled in | [docs/spike/RUNBOOK.md](docs/spike/RUNBOOK.md#fill-in-the-gono-go-table) |

## Scaffold

| Item | Status |
| --- | --- |
| Gateway with `GET /health`, environment validation, correlation-ID logging, Vitest | done |
| Contracts: JSON Schema with generated Dart and TypeScript types, and a CI staleness check | done |
| Mobile app: placeholder screen, one widget test, state-management ADR | done |
| CI: gateway, contracts, mobile (with the spike app) and evaluation jobs | done |

## Milestone 1

Started on 2026-11-01 at the user's request, in parallel with the device measurements. Parts that depend on the go/no-go decisions wait for them.

| Item | Status | Where |
| --- | --- | --- |
| Durable job state machine and crash-safe job store on the phone | done | [ADR 0007](docs/decisions/0007-job-store-and-routing-rules.md) |
| Deterministic routing policy in Dart | done, size limits unset until measured | [ADR 0007](docs/decisions/0007-job-store-and-routing-rules.md) |
| Gateway job API with idempotent submits and SQLite storage | done, no inference backend | [ADR 0008](docs/decisions/0008-gateway-job-api.md) |
| Mac inference backend through any OpenAI-compatible server | done; the model is not measured | [ADR 0011](docs/decisions/0011-mac-inference-backend-and-mdns.md) |
| Phone recording, transcription, extraction, validation and escalation | done with candidate models; not run on a device | [ADR 0012](docs/decisions/0012-mobile-pipeline.md) |
| Pairing, session tokens, revocation, per-device jobs | done on the gateway and the phone | [ADR 0009](docs/decisions/0009-pairing-and-sessions.md) |
| TLS 1.3 with a pinned self-signed certificate, pairing proofs | done on the gateway and the phone | [ADR 0010](docs/decisions/0010-tls-and-pinned-pairing.md) |
| mDNS discovery | done; tested on Linux, not on a phone | [ADR 0011](docs/decisions/0011-mac-inference-backend-and-mdns.md) |
| Phone-only, Mac-only and hybrid evaluation harness | done; not run on devices or a real model server | [benchmarks/harness](benchmarks/harness) |
