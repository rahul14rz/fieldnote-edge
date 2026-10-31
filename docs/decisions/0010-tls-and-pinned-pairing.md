# ADR 0010: TLS with a pinned self-signed certificate, and pairing proofs bound to it

- Status: accepted
- Date: 2026-11-01

## Context

[ADR 0009](0009-pairing-and-sessions.md) added pairing codes, device secrets and session tokens, but over plain HTTP. On a shared network those credentials and the transcripts would be readable. A home or office LAN has no public hostname, so a certificate from a public certificate authority isn't available. The phone has to trust the Mac's own certificate, and it has to get that trust without a man in the middle being able to substitute another certificate during pairing.

## Decision

### The certificate

- On first start, the gateway creates an EC P-256 key and a self-signed certificate valid for 10 years, with `selfsigned` 5.5.0. They live in `$DATA_DIR/tls/`, and the key file is mode 0600. Later starts reuse them, because the phone pins this exact certificate.
- The fingerprint is the SHA-256 of the certificate's DER encoding, in lowercase hex. The server logs it at startup, and `fieldnote-gateway pair` prints its first 16 characters.
- The server accepts TLS 1.3 only and does not answer plain HTTP.
- `selfsigned` was chosen after `@peculiar/x509` 2.2.0, which needs a global `reflect-metadata` polyfill. Version 3.x of that library was four days old when this was written.

### Pairing without sending the code

A typed code alone does not stop a man in the middle. A device that intercepts the connection can present its own certificate, read the code from the request, and replay it to the real gateway. So the phone never sends the code:

1. The phone opens a TLS connection and reads the fingerprint `F` of the certificate it was given.
2. It sends `proof = HMAC-SHA256(key = code, "fieldnote-pair-v1|client|" + F)`.
3. When it created the code, the gateway stored only `SHA-256(proof)` computed over its own fingerprint. A proof over any other fingerprint matches nothing.
4. The gateway answers with `serverProof = HMAC-SHA256(code, "fieldnote-pair-v1|server|" + F)`. The phone computes the same value and accepts the response only if they match. Then it pins `F` for every later connection.

A man in the middle sees only an HMAC over its own fingerprint, which the gateway rejects. Recovering the code from that HMAC means searching about 2^50 codes before the code expires 5 minutes later, and the code works once.

### Pinning on the phone

The phone trusts no certificate authority for the gateway. It accepts a connection only if the certificate's SHA-256 fingerprint equals the pinned value, and it checks this before it sends any request body. The gateway tests use the same rule: the pinned certificate is the only trusted CA, and `checkServerIdentity` compares the fingerprint.

## Consequences

- Deleting `$DATA_DIR/tls/` makes every phone pair again. That is also the way to rotate the key.
- With TLS and authentication in place, `HOST` can be set to a LAN address. The default stays `127.0.0.1` ([ADR 0006](0006-gateway-binds-loopback-until-pairing.md)) until the phone side and mDNS discovery exist, so that nothing is exposed before it is used.
- The 10-year validity is a placeholder. The phone checks the fingerprint, not the dates, so expiry doesn't cause failures. Rotation is a manual action.
