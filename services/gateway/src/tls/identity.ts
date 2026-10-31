import { X509Certificate } from "node:crypto";
import { chmodSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

import selfsigned from "selfsigned";

export interface TlsIdentity {
  key: string;
  cert: string;
  /** SHA-256 of the certificate's DER encoding, lowercase hex without colons. */
  fingerprint: string;
}

const VALIDITY_YEARS = 10;

export function fingerprintOf(certPem: string): string {
  return new X509Certificate(certPem).fingerprint256.replaceAll(":", "").toLowerCase();
}

/**
 * Loads the gateway's TLS key and self-signed certificate from `dir`, or
 * creates them on first start. The phone pins the certificate's fingerprint
 * at pairing, so the same certificate must survive restarts: regenerating it
 * forces every phone to pair again.
 */
export async function loadOrCreateIdentity(dir: string): Promise<TlsIdentity> {
  const keyPath = join(dir, "gateway-key.pem");
  const certPath = join(dir, "gateway-cert.pem");
  if (existsSync(keyPath) && existsSync(certPath)) {
    const cert = readFileSync(certPath, "utf8");
    return { key: readFileSync(keyPath, "utf8"), cert, fingerprint: fingerprintOf(cert) };
  }
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  const notBeforeDate = new Date();
  const notAfterDate = new Date(notBeforeDate);
  notAfterDate.setUTCFullYear(notAfterDate.getUTCFullYear() + VALIDITY_YEARS);
  const generated = await selfsigned.generate(
    [{ name: "commonName", value: "fieldnote-gateway" }],
    {
      keyType: "ec",
      curve: "P-256",
      algorithm: "sha256",
      notBeforeDate,
      notAfterDate,
    },
  );
  writeFileSync(keyPath, generated.private, { mode: 0o600 });
  chmodSync(keyPath, 0o600);
  writeFileSync(certPath, generated.cert, { mode: 0o644 });
  return {
    key: generated.private,
    cert: generated.cert,
    fingerprint: fingerprintOf(generated.cert),
  };
}
