# ADR 0006: The gateway listens on loopback until pairing exists

- Status: accepted
- Date: 2026-10-31

## Context

The gateway will eventually serve the phone over the local network. Pairing, session credentials and TLS are not built yet (see [security](../security.md)). A gateway on the LAN without them would accept requests from any device on the network.

## Decision

`HOST` defaults to `127.0.0.1`. Binding to another address requires setting `HOST` explicitly. A test in `services/gateway/test/env.test.ts` fails if the default changes.

## Consequences

- The phone can't reach the gateway with the default settings. That is intended for Milestone 0, which has no phone-to-Mac traffic.
- When pairing and TLS land, a new ADR decides the LAN default.
