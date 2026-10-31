# ADR 0009: Pairing, device credentials and session tokens

- Status: accepted
- Date: 2026-11-01

## Context

The phone will send transcripts of customer meetings to the Mac. Only a phone the user has paired may submit or read jobs. [docs/security.md](../security.md) lists the planned mechanisms. This ADR covers the credential part. TLS with certificate pinning and mDNS discovery come in the next change, so for now the gateway still listens on loopback only ([ADR 0006](0006-gateway-binds-loopback-until-pairing.md)).

## Decision

### Flow

1. On the Mac, the user runs `fieldnote-gateway pair` (`node services/gateway/dist/src/cli.js pair`). It prints a one-time pairing code.
2. The user types the code on the phone. The phone sends `POST /v1/pairing` with the code and a device name.
3. The gateway answers with a device ID and a device secret. The phone keeps the secret in secure storage. The gateway keeps only its SHA-256 hash.
4. Before calling the job API, the phone exchanges the device ID and secret for a session token with `POST /v1/sessions`.
5. Every `/v1/jobs` request carries `Authorization: Bearer <session token>`. Without a valid token the gateway answers 401.
6. `fieldnote-gateway revoke <deviceId>` marks the device revoked and deletes its sessions. Its next request gets 401, and it can't get a new session.

### Values

| Item | Format | Lifetime | Stored as |
| --- | --- | --- | --- |
| Pairing code | 10 Crockford base32 characters from `crypto.randomInt`, about 50 bits | 5 minutes, single use | SHA-256 hash |
| Device secret | 32 bytes from `crypto.randomBytes`, base64url | Until revoked | SHA-256 hash |
| Session token | 32 bytes from `crypto.randomBytes`, base64url | 15 minutes | SHA-256 hash |

- The pairing code is short so that a person can type it. Three things limit guessing: the code works once, it expires after 5 minutes, and after 5 failed pairing attempts in 60 seconds the gateway answers 429 to every pairing request until the window passes.
- All three values are random with enough entropy that a slow password hash adds nothing. SHA-256 means a leaked database does not leak a usable credential.
- Marking a code used and creating the device happen in one SQLite transaction, so two phones racing with one code can't both pair.
- The two-level credential keeps the long-lived secret off most requests. Only `POST /v1/sessions` sends it.

### Jobs belong to a device

Jobs are keyed by (device ID, job ID). A device can read only its own jobs. Another device's job ID answers 404, so the response does not reveal that the job exists.

## Consequences

- Until TLS lands, these credentials are only as safe as the loopback interface. Binding the gateway to the LAN before TLS would send them in clear text, which is why ADR 0006 still applies.
- The pairing failure limit is per gateway process and kept in memory. A restart resets it. That is acceptable while the gateway is single-user and on loopback.
