# Gateway

The gateway is a Fastify and TypeScript service that runs on the Mac. In a later milestone it will run the larger Gemma model for jobs the phone escalates. It does not decide where a job runs; the Flutter app does that ([ADR 0002](../../docs/decisions/0002-routing-in-the-app.md)).

Implemented so far:

- `GET /health` returns the `HealthResponse` contract from `packages/contracts`.
- A job API for summarize jobs: `POST /v1/jobs`, `GET /v1/jobs/:jobId` and `GET /v1/jobs/:jobId/summary`. Submits are idempotent on the job ID. Jobs are stored in SQLite and survive a restart. Every model answer is validated against `MeetingSummary`. [ADR 0008](../../docs/decisions/0008-gateway-job-api.md) has the status codes and failure kinds.
- Startup validates the environment and exits with code 1, naming the bad variable, if a value is invalid.
- Logs are structured JSON (pino). Each request log line carries a `correlationId`. The gateway takes the ID from the `x-request-id` request header if the header matches `^[A-Za-z0-9._-]{1,64}$`, otherwise it generates a UUID, and it returns the ID in the `x-request-id` response header.

- Pairing and session tokens ([ADR 0009](../../docs/decisions/0009-pairing-and-sessions.md)). Every `/v1/jobs` request needs `Authorization: Bearer <session token>`.

Not implemented yet: a real inference backend (`INFERENCE_BACKEND=none` is the only value, so `POST /v1/jobs` answers 503), TLS, and mDNS discovery.

## Environment

| Variable | Default | Allowed values |
| --- | --- | --- |
| `HOST` | `127.0.0.1` | Any interface address |
| `PORT` | `8787` | 0 to 65535 |
| `LOG_LEVEL` | `info` | `fatal`, `error`, `warn`, `info`, `debug`, `trace`, `silent` |
| `DATA_DIR` | `./data` | Directory for `gateway.sqlite` |
| `INFERENCE_BACKEND` | `none` | `none` |

By default the gateway listens only on loopback. Pairing and TLS don't exist yet, so binding to the LAN would expose an unauthenticated service.

## Run

From the repository root (requires Node.js 22 or later and pnpm 10):

```bash
pnpm install
```

```bash
pnpm --filter @fieldnote/gateway build
```

```bash
PORT=8787 node services/gateway/dist/src/server.js
```

In another terminal:

```bash
curl -sS http://127.0.0.1:8787/health
```

Expected response:

```json
{"status":"ok","service":"fieldnote-gateway","version":"0.0.0"}
```

## Pair a device

Build the gateway first. Then, on the Mac:

```bash
node services/gateway/dist/src/cli.js pair
```

The command prints a 10-character code that works once, for 5 minutes. List paired devices, and revoke one:

```bash
node services/gateway/dist/src/cli.js devices
node services/gateway/dist/src/cli.js revoke <deviceId>
```

The CLI and the server must use the same `DATA_DIR`.

## Checks

```bash
pnpm --filter @fieldnote/gateway lint
pnpm --filter @fieldnote/gateway format:check
pnpm --filter @fieldnote/gateway typecheck
pnpm --filter @fieldnote/gateway test
```

The tests start the server on a real socket (port 0) with a fresh SQLite file and call it with `fetch`. The job tests use a scripted backend. They cover the full flow, invalid answers, idempotent resubmits, the requeue after a backend error, and a restart that reruns a job left `processing`. The startup test runs `src/server.ts` with `PORT=not-a-number` and asserts that it exits with code 1.
