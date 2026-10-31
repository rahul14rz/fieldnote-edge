# Gateway

The gateway is a Fastify and TypeScript service that runs on the Mac. In a later milestone it will run the larger Gemma model for jobs the phone escalates. It does not decide where a job runs; the Flutter app does that ([ADR 0002](../../docs/decisions/0002-routing-in-the-app.md)).

Implemented so far:

- `GET /health` returns the `HealthResponse` contract from `packages/contracts`.
- A job API for summarize jobs: `POST /v1/jobs`, `GET /v1/jobs/:jobId` and `GET /v1/jobs/:jobId/summary`. Submits are idempotent on the job ID. Jobs are stored in SQLite and survive a restart. Every model answer is validated against `MeetingSummary`. [ADR 0008](../../docs/decisions/0008-gateway-job-api.md) has the status codes and failure kinds.
- Startup validates the environment and exits with code 1, naming the bad variable, if a value is invalid.
- Logs are structured JSON (pino). Each request log line carries a `correlationId`. The gateway takes the ID from the `x-request-id` request header if the header matches `^[A-Za-z0-9._-]{1,64}$`, otherwise it generates a UUID, and it returns the ID in the `x-request-id` response header.

- Pairing and session tokens ([ADR 0009](../../docs/decisions/0009-pairing-and-sessions.md)). Every `/v1/jobs` request needs `Authorization: Bearer <session token>`.
- HTTPS only, TLS 1.3, with a self-signed certificate created on first start in `$DATA_DIR/tls/`. Pairing proofs bind the code to the certificate fingerprint ([ADR 0010](../../docs/decisions/0010-tls-and-pinned-pairing.md)).

- Inference through any local server that implements the OpenAI chat completions API, with greedy decoding ([ADR 0011](../../docs/decisions/0011-mac-inference-backend-and-mdns.md)). Without a backend, `POST /v1/jobs` answers 503.
- mDNS advertising of `_fieldnote._tcp` when the gateway listens beyond loopback.

## Serve the phone

Start a model server that implements `POST /v1/chat/completions`, for example llama.cpp's `llama-server` or Ollama, with the Gemma 4 build you measured. Then start the gateway on the LAN:

```bash
HOST=0.0.0.0 INFERENCE_BACKEND=openai-compatible INFERENCE_URL=http://127.0.0.1:8080/v1 INFERENCE_MODEL=<model name> node services/gateway/dist/src/server.js
```

The model server URL and name above are placeholders for your setup. No model server was run in this repository's development environment.

## Environment

| Variable | Default | Allowed values |
| --- | --- | --- |
| `HOST` | `127.0.0.1` | Any interface address |
| `PORT` | `8787` | 0 to 65535 |
| `LOG_LEVEL` | `info` | `fatal`, `error`, `warn`, `info`, `debug`, `trace`, `silent` |
| `DATA_DIR` | `./data` | Directory for `gateway.sqlite` |
| `INFERENCE_BACKEND` | `none` | `none`, or `openai-compatible` for a local model server |
| `INFERENCE_URL` | none | Base URL ending in `/v1`, required with `openai-compatible` |
| `INFERENCE_MODEL` | none | Model name the server expects, required with `openai-compatible` |
| `INFERENCE_TIMEOUT_MS` | `600000` | Positive integer |
| `INFERENCE_MAX_OUTPUT_TOKENS` | `2048` | Positive integer |
| `MDNS` | `auto` | `auto` (advertise only beyond loopback), `on`, `off` |

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

In another terminal, from the repository root, pin the gateway's public key. The certificate is self-signed, so `-k` skips the CA check, and `--pinnedpubkey` still rejects any other key:

```bash
PIN=$(openssl x509 -in data/tls/gateway-cert.pem -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64)
curl -sS -k --pinnedpubkey "sha256//$PIN" https://127.0.0.1:8787/health
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

The command prints a 10-character code that works once, for 5 minutes, and the start of the certificate fingerprint. The phone sends a proof derived from the code and the fingerprint, not the code itself. List paired devices, and revoke one:

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
