# Evaluation harness

These tools produce the phone-only, Mac-only and hybrid comparison from the same fixed prompt set (`apps/spike/assets/prompt_set.json`).

- `src/mac-arm.mjs` sends every prompt case to an OpenAI-compatible model server on the Mac. Decoding is greedy and streamed, so time to first token can be measured. It writes a run record in the spike's format ([`run-record.schema.json`](../results/run-record.schema.json)), so `summarize_runs.py` reads phone and Mac runs alike. The harness can't see the server process's memory. Record that with `footprint` or Activity Monitor (see the [runbook](../../docs/spike/RUNBOOK.md)).
- `src/hybrid.mjs` takes one phone run record and one Mac run record. For each prompt case it pairs repetitions in order and reports three arms: phone only, Mac only, and hybrid. In the hybrid arm a case runs on the phone and, when the phone output is not a valid `MeetingSummary`, on the Mac as well, so its time is the phone time plus the Mac time. With `--max-words N`, a case whose transcript is over N words goes to the Mac directly. That matches the routing rules in [ADR 0007](../../docs/decisions/0007-job-store-and-routing-rules.md). The times exclude network transfer between the phone and the Mac.

Validity uses `checkOutput` from `packages/contracts/scripts/validate-outputs.mjs`, the same rule as the gateway and the phone.

## Run

```bash
pnpm --filter @fieldnote/harness mac-arm --url http://127.0.0.1:8080/v1 --model <model name> --output "$PWD/benchmarks/results/raw/macbook-air-m4/mac-arm.json"
pnpm --filter @fieldnote/harness hybrid --phone "$PWD/benchmarks/results/raw/oneplus-11r/<runId>.json" --mac "$PWD/benchmarks/results/raw/macbook-air-m4/mac-arm.json" --output "$PWD/benchmarks/results/raw/hybrid.json"
```

Pass absolute paths, because pnpm runs the scripts inside `benchmarks/harness`. These two commands have not been run against a real model server or real phone records.

## Tests

```bash
pnpm --filter @fieldnote/harness test
```

The tests stream from a fake model server, check the run record against the schema, and read it back with `summarize_runs.py`. They also check the hybrid arithmetic on synthetic records.
