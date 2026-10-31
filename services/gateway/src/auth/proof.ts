import { createHmac } from "node:crypto";

/**
 * Pairing proofs bind the pairing code to the TLS certificate each side saw.
 *
 * The phone never sends the code. It sends HMAC-SHA256(code, "client" + the
 * fingerprint of the certificate it connected to). The gateway accepts the
 * proof only if it matches its own fingerprint, so a man in the middle with a
 * different certificate gets a proof the gateway rejects. The gateway answers
 * with HMAC-SHA256(code, "server" + its fingerprint), which proves to the
 * phone that the other end knows the code.
 */
const LABEL = "fieldnote-pair-v1";

function hmac(code: string, role: "client" | "server", fingerprint: string): string {
  return createHmac("sha256", code).update(`${LABEL}|${role}|${fingerprint}`).digest("hex");
}

export const clientProof = (code: string, fingerprint: string): string =>
  hmac(code, "client", fingerprint);
export const serverProof = (code: string, fingerprint: string): string =>
  hmac(code, "server", fingerprint);
