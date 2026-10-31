import { createHash, randomBytes, randomInt } from "node:crypto";

const CROCKFORD = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

/** Ten Crockford base32 characters (50 bits) from a CSPRNG, for a person to type. */
export function newPairingCode(): string {
  let code = "";
  for (let i = 0; i < 10; i++) code += CROCKFORD.charAt(randomInt(CROCKFORD.length));
  return code;
}

/** 32 random bytes, base64url without padding (43 characters). */
export function newSecret(): string {
  return randomBytes(32).toString("base64url");
}

export function newDeviceId(): string {
  return `dev_${randomBytes(16).toString("hex")}`;
}

/**
 * Codes, secrets and tokens are high-entropy random values, so a plain
 * SHA-256 is enough to store them; a slow password hash adds nothing here.
 */
export function hashSecret(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}
