import { DatabaseSync } from "node:sqlite";

import { clientProof, serverProof } from "./proof.js";
import { hashSecret, newDeviceId, newPairingCode, newSecret } from "./tokens.js";

export interface Device {
  deviceId: string;
  name: string;
  pairedAt: string;
  revokedAt: string | null;
}

export interface AuthPolicy {
  pairingCodeTtlMs: number;
  sessionTtlMs: number;
}

export const DEFAULT_AUTH_POLICY: AuthPolicy = {
  pairingCodeTtlMs: 5 * 60_000,
  sessionTtlMs: 15 * 60_000,
};

/**
 * Pairing codes, paired devices and sessions. Only SHA-256 hashes of codes,
 * device secrets and session tokens are stored.
 */
export class AuthStore {
  private readonly db: DatabaseSync;

  constructor(
    path: string,
    private readonly now: () => Date,
    private readonly policy: AuthPolicy = DEFAULT_AUTH_POLICY,
  ) {
    this.db = new DatabaseSync(path);
    this.db.exec(`
      PRAGMA journal_mode = WAL;
      PRAGMA busy_timeout = 5000;
      CREATE TABLE IF NOT EXISTS pairing_offers (
        proof_hash TEXT PRIMARY KEY,
        server_proof TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        used_at TEXT
      );
      CREATE TABLE IF NOT EXISTS devices (
        device_id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        secret_hash TEXT NOT NULL,
        paired_at TEXT NOT NULL,
        revoked_at TEXT
      );
      CREATE TABLE IF NOT EXISTS sessions (
        token_hash TEXT PRIMARY KEY,
        device_id TEXT NOT NULL REFERENCES devices (device_id),
        expires_at TEXT NOT NULL
      );
    `);
  }

  /**
   * Creates a single-use pairing code for the certificate with `fingerprint`.
   * The code itself is not stored: only the hash of the proof a phone must
   * send, and the proof the gateway answers with.
   */
  createPairingCode(fingerprint: string): { code: string; expiresAt: string } {
    const code = newPairingCode();
    const expiresAt = this.iso(this.now().getTime() + this.policy.pairingCodeTtlMs);
    this.db
      .prepare("INSERT INTO pairing_offers (proof_hash, server_proof, expires_at) VALUES (?, ?, ?)")
      .run(hashSecret(clientProof(code, fingerprint)), serverProof(code, fingerprint), expiresAt);
    return { code, expiresAt };
  }

  /**
   * Redeems a pairing proof. Returns the new device credential and the server
   * proof, or null if the proof matches no unexpired, unused offer. Marking the
   * offer used and creating the device happen in one transaction, so an offer
   * pairs once.
   */
  redeemPairingProof(
    proof: string,
    deviceName: string,
  ): { deviceId: string; deviceSecret: string; serverProof: string } | null {
    const nowIso = this.iso(this.now().getTime());
    this.db.exec("BEGIN IMMEDIATE");
    try {
      const offer = this.db
        .prepare(
          "SELECT server_proof FROM pairing_offers WHERE proof_hash = ? AND used_at IS NULL AND expires_at > ?",
        )
        .get(hashSecret(proof), nowIso) as { server_proof: string } | undefined;
      if (!offer) {
        this.db.exec("ROLLBACK");
        return null;
      }
      this.db
        .prepare("UPDATE pairing_offers SET used_at = ? WHERE proof_hash = ?")
        .run(nowIso, hashSecret(proof));
      const deviceId = newDeviceId();
      const deviceSecret = newSecret();
      this.db
        .prepare(
          "INSERT INTO devices (device_id, name, secret_hash, paired_at) VALUES (?, ?, ?, ?)",
        )
        .run(deviceId, deviceName, hashSecret(deviceSecret), nowIso);
      this.db.exec("COMMIT");
      return { deviceId, deviceSecret, serverProof: offer.server_proof };
    } catch (error) {
      this.db.exec("ROLLBACK");
      throw error;
    }
  }

  /** Issues a session token for a paired, unrevoked device with the right secret. */
  createSession(
    deviceId: string,
    deviceSecret: string,
  ): { sessionToken: string; expiresAt: string } | null {
    const device = this.db
      .prepare("SELECT secret_hash FROM devices WHERE device_id = ? AND revoked_at IS NULL")
      .get(deviceId) as { secret_hash: string } | undefined;
    if (device?.secret_hash !== hashSecret(deviceSecret)) return null;
    const sessionToken = newSecret();
    const expiresAt = this.iso(this.now().getTime() + this.policy.sessionTtlMs);
    this.db
      .prepare("INSERT INTO sessions (token_hash, device_id, expires_at) VALUES (?, ?, ?)")
      .run(hashSecret(sessionToken), deviceId, expiresAt);
    return { sessionToken, expiresAt };
  }

  /** The device behind a session token, or null if the token is unknown, expired or revoked. */
  authenticate(sessionToken: string): string | null {
    const row = this.db
      .prepare(
        `SELECT s.device_id FROM sessions s JOIN devices d ON d.device_id = s.device_id
         WHERE s.token_hash = ? AND s.expires_at > ? AND d.revoked_at IS NULL`,
      )
      .get(hashSecret(sessionToken), this.iso(this.now().getTime())) as
      { device_id: string } | undefined;
    return row?.device_id ?? null;
  }

  /** Revokes a device and deletes its sessions. Returns false for an unknown device. */
  revoke(deviceId: string): boolean {
    const result = this.db
      .prepare("UPDATE devices SET revoked_at = ? WHERE device_id = ? AND revoked_at IS NULL")
      .run(this.iso(this.now().getTime()), deviceId);
    this.db.prepare("DELETE FROM sessions WHERE device_id = ?").run(deviceId);
    return Number(result.changes) === 1;
  }

  devices(): Device[] {
    return (
      this.db
        .prepare("SELECT device_id, name, paired_at, revoked_at FROM devices ORDER BY paired_at")
        .all() as {
        device_id: string;
        name: string;
        paired_at: string;
        revoked_at: string | null;
      }[]
    ).map((r) => ({
      deviceId: r.device_id,
      name: r.name,
      pairedAt: r.paired_at,
      revokedAt: r.revoked_at,
    }));
  }

  close(): void {
    this.db.close();
  }

  private iso(ms: number): string {
    return new Date(ms).toISOString();
  }
}
