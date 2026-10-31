# Gateway client

`fieldnote_gateway_client` is the Dart package the phone uses to talk to the Mac gateway. It has no Flutter dependency, so `dart test` runs it on any machine.

- `discoverGateways()` browses mDNS for `_fieldnote._tcp`. It returns addresses and the fingerprint prefix from the TXT record. Discovery never grants trust.
- `pair(address, code:, deviceName:)` reads the gateway's certificate fingerprint and sends a proof bound to it instead of the code. It checks the gateway's server proof, then returns a `PairedGateway` with the pinned fingerprint ([ADR 0010](../../docs/decisions/0010-tls-and-pinned-pairing.md)). Codes may be typed in lower case, with spaces or a dash.
- `GatewayClient(paired)` makes every request over TLS pinned to that fingerprint. No certificate authority is trusted. It gets a session token when needed, reuses it until a minute before expiry, and gets a new one once on 401. Methods: `health`, `submit`, `status`, `summary`.
- Errors are typed:
  - `PinMismatch`: a different certificate.
  - `GatewayUnreachable`: network, TLS or timeout.
  - `GatewayRejected`: an HTTP error status, with the code.
  - `ServerProofMismatch`: the other end doesn't know the pairing code.

Keep `PairedGateway.deviceSecret` in secure storage. The mobile app uses `flutter_secure_storage`.

## Tests

The integration tests start the built gateway as a child process, with a fake OpenAI-compatible model server:

```bash
pnpm --filter @fieldnote/gateway build
cd packages/gateway_client
dart pub get
dart test
```

The tests cover pairing and a job run to a validated summary. They also cover the code formats people type, a wrong code, a pin mismatch, an unreachable gateway, revocation, an impostor with a wrong server proof, and mDNS discovery. `test/proof_test.dart` checks the shared vector in `packages/contracts/fixtures/pairing-proof-vector.json`, which the gateway's tests also check.
