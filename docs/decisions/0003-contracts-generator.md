# ADR 0003: JSON Schema as the contract source, with quicktype generating Dart and TypeScript

- Status: accepted
- Date: 2026-10-31

## Context

The app (Dart) and the gateway (TypeScript) exchange data. If each side defines its own types, they drift. The project needs one source and types for both languages.

Options considered:

- **OpenAPI plus a generator per language.** OpenAPI describes endpoints as well as payloads. Only one endpoint exists (`GET /health`), and the main shared shape, `MeetingSummary`, is not an HTTP payload yet: the phone produces it locally. Two generators would also mean two sets of behavior to check.
- **JSON Schema plus json-schema-to-typescript for TypeScript and a Dart generator such as `json_serializable` with hand-written models.** The Dart side would be hand-written, which is the drift this ADR exists to stop.
- **JSON Schema plus quicktype for both languages.** One tool, one input, both outputs. quicktype 26.0.0 was the current npm release when this ADR was written.

## Decision

- Schemas live in `packages/contracts/schema/*.schema.json` (JSON Schema draft-07).
- `packages/contracts/scripts/generate.mjs` runs quicktype 26.0.0 (pinned in `package.json`) and writes `generated/ts/index.ts` and `dart/lib/fieldnote_contracts.dart`.
- `pnpm --filter @fieldnote/contracts check` regenerates the files in memory and exits with code 1 if the committed files differ. CI runs it.
- Ajv validates fixtures against the schema in the TypeScript tests. The Dart tests parse the same fixtures and assert that `toJson()` reproduces them exactly. The gateway uses the schema file directly as its Fastify response schema.
- Every object property is listed in `required`. A value that can be absent is nullable (`"type": ["string", "null"]`), never optional. The generator script refuses optional properties.

## Why every property is required

The first version had an optional `Participant.role`. The Dart class quicktype generated serializes an absent `role` as `"role": null`, and the schema rejected that output. A Dart round-trip test caught it. Required-and-nullable fields avoid the mismatch, and they are also easier for a model to fill in, because every key always appears.

## What quicktype gets wrong, and the workarounds

- A string with `"format": "date"` becomes a `Date` in TypeScript, but the JSON value is a string. `dueDate` uses a `pattern` (`^\d{4}-\d{2}-\d{2}$`) instead of `format`.
- The Dart output does not follow `dart format` or the lint rules, so `packages/contracts/dart/analysis_options.yaml` excludes the generated file from analysis.
- Dart `fromJson` does not validate. A wrong type fails with a cast error, and constraints such as `minLength` and `pattern` are not checked. Data from an untrusted source (a model's output, the network) has to be validated against the schema before it is trusted. In Milestone 1 that is the job of the validation step that decides escalation.

## Consequences

- Changing a contract means editing a schema, running `generate`, and committing all three files. CI fails if the generated files are stale.
- Replacing quicktype later means changing one script and regenerating. The schemas don't change.
