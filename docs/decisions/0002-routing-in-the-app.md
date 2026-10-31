# ADR 0002: The routing policy lives in the Flutter app, in Dart, and is deterministic

- Status: accepted
- Date: 2026-10-31

## Context

Each job (transcribe a recording, summarize a transcript) runs either on the phone or on the Mac. The app must keep working when the Mac is off, so the decision has to be made where the job starts. That place is the phone.

An earlier plan had a TypeScript routing engine package next to the gateway. The gateway is reachable only when the Mac is on, so a decision made there can't cover the phone-only case. The same rules would also have to exist in two languages.

## Decision

- The routing policy is Dart code inside `apps/mobile`. There is no TypeScript routing package.
- The gateway does not decide where a job runs. It accepts or rejects work it is sent.
- Routing is a pure function of inputs known when the decision is made: task type, input size (for example audio duration or transcript tokens), the result of validating an on-device output, whether the Mac is paired and reachable, and the user's settings. The same inputs always give the same route.
- Historical accuracy of a task or model is **not** a routing input. Results from earlier jobs never change later routes. Routing does not learn.

No routing code exists yet. It is Milestone 1 work, and it will use the thresholds the spike confirms ([ADR 0001](0001-spike-decision-gates.md)).

## Consequences

- One implementation, unit-testable with plain Dart tests and no network.
- A route can be explained after the fact from the inputs alone, which keeps the phone-only, Mac-only and hybrid evaluation reproducible.
- Improving routing means changing the code or a threshold in a reviewed commit, not collecting more history.
