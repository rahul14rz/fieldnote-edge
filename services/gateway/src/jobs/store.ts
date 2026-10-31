import { createHash } from "node:crypto";
import { DatabaseSync } from "node:sqlite";

import type {
  JobErrorKind,
  JobState,
  JobStatus,
  JobSubmission,
  MeetingSummary,
} from "@fieldnote/contracts";

export interface StoredJob {
  deviceId: string;
  status: JobStatus;
  submission: JobSubmission;
  summary: MeetingSummary | null;
}

export type SubmitResult =
  | { outcome: "created"; job: StoredJob }
  | { outcome: "existing"; job: StoredJob }
  | { outcome: "requeued"; job: StoredJob }
  | { outcome: "conflict"; job: StoredJob };

interface Row {
  device_id: string;
  job_id: string;
  request_hash: string;
  request: string;
  state: JobState;
  attempts: number;
  summary: string | null;
  error_kind: JobErrorKind | null;
  error_message: string | null;
}

const NOW = "strftime('%Y-%m-%dT%H:%M:%fZ', 'now')";

function requestHash(submission: JobSubmission): string {
  const { kind, transcript, language } = submission;
  return createHash("sha256")
    .update(JSON.stringify([kind, transcript, language]))
    .digest("hex");
}

function toJob(row: Row): StoredJob {
  return {
    deviceId: row.device_id,
    status: {
      jobId: row.job_id,
      state: row.state,
      attempts: row.attempts,
      error:
        row.error_kind === null ? null : { kind: row.error_kind, message: row.error_message ?? "" },
    },
    submission: JSON.parse(row.request) as JobSubmission,
    summary: row.summary === null ? null : (JSON.parse(row.summary) as MeetingSummary),
  };
}

/**
 * Durable gateway jobs in SQLite, keyed by (device, job ID). Every state
 * change is one statement or one transaction, so a crash never leaves a
 * half-applied change.
 */
export class JobStore {
  private readonly db: DatabaseSync;

  constructor(path: string) {
    this.db = new DatabaseSync(path);
    this.db.exec(`
      PRAGMA journal_mode = WAL;
      PRAGMA busy_timeout = 5000;
      CREATE TABLE IF NOT EXISTS jobs (
        device_id TEXT NOT NULL,
        job_id TEXT NOT NULL,
        request_hash TEXT NOT NULL,
        request TEXT NOT NULL,
        state TEXT NOT NULL CHECK (state IN ('queued', 'processing', 'completed', 'failed')),
        attempts INTEGER NOT NULL DEFAULT 0,
        summary TEXT,
        error_kind TEXT CHECK (error_kind IN ('invalid_output', 'backend_error')),
        error_message TEXT,
        created_at TEXT NOT NULL DEFAULT (${NOW}),
        updated_at TEXT NOT NULL DEFAULT (${NOW}),
        PRIMARY KEY (device_id, job_id)
      );
    `);
  }

  /** A job as seen by the device that submitted it. Other devices get undefined. */
  get(deviceId: string, jobId: string): StoredJob | undefined {
    const row = this.db
      .prepare("SELECT * FROM jobs WHERE device_id = ? AND job_id = ?")
      .get(deviceId, jobId) as Row | undefined;
    return row && toJob(row);
  }

  /**
   * Idempotent on (device, jobId). The same body returns the stored job; a
   * job that failed with backend_error is queued again, because that failure
   * may go away. A different body for an existing jobId is a conflict.
   */
  submit(deviceId: string, submission: JobSubmission): SubmitResult {
    return this.transaction(() => {
      const hash = requestHash(submission);
      const row = this.db
        .prepare("SELECT * FROM jobs WHERE device_id = ? AND job_id = ?")
        .get(deviceId, submission.jobId) as Row | undefined;
      if (!row) {
        this.db
          .prepare(
            "INSERT INTO jobs (device_id, job_id, request_hash, request, state) VALUES (?, ?, ?, ?, 'queued')",
          )
          .run(deviceId, submission.jobId, hash, JSON.stringify(submission));
        return { outcome: "created", job: this.mustGet(deviceId, submission.jobId) };
      }
      const existing = toJob(row);
      if (row.request_hash !== hash) return { outcome: "conflict", job: existing };
      if (row.state === "failed" && row.error_kind === "backend_error") {
        this.setState(deviceId, submission.jobId, "queued", null);
        return { outcome: "requeued", job: this.mustGet(deviceId, submission.jobId) };
      }
      return { outcome: "existing", job: existing };
    });
  }

  /** Moves the oldest queued job to processing and returns it. */
  claimNext(): StoredJob | undefined {
    return this.transaction(() => {
      const row = this.db
        .prepare(
          "SELECT device_id, job_id FROM jobs WHERE state = 'queued' ORDER BY created_at, rowid LIMIT 1",
        )
        .get() as { device_id: string; job_id: string } | undefined;
      if (!row) return undefined;
      this.db
        .prepare(
          `UPDATE jobs SET state = 'processing', attempts = attempts + 1, error_kind = NULL,
           error_message = NULL, updated_at = ${NOW} WHERE device_id = ? AND job_id = ?`,
        )
        .run(row.device_id, row.job_id);
      return this.mustGet(row.device_id, row.job_id);
    });
  }

  complete(deviceId: string, jobId: string, summary: MeetingSummary): void {
    this.db
      .prepare(
        `UPDATE jobs SET state = 'completed', summary = ?, updated_at = ${NOW}
         WHERE device_id = ? AND job_id = ? AND state = 'processing'`,
      )
      .run(JSON.stringify(summary), deviceId, jobId);
  }

  fail(deviceId: string, jobId: string, kind: JobErrorKind, message: string): void {
    this.setState(deviceId, jobId, "failed", { kind, message });
  }

  /** Jobs left processing by a crash go back to queued. Returns how many. */
  recoverInterrupted(): number {
    const result = this.db
      .prepare(`UPDATE jobs SET state = 'queued', updated_at = ${NOW} WHERE state = 'processing'`)
      .run();
    return Number(result.changes);
  }

  close(): void {
    this.db.close();
  }

  private setState(
    deviceId: string,
    jobId: string,
    state: JobState,
    error: { kind: JobErrorKind; message: string } | null,
  ): void {
    this.db
      .prepare(
        `UPDATE jobs SET state = ?, error_kind = ?, error_message = ?, updated_at = ${NOW}
         WHERE device_id = ? AND job_id = ?`,
      )
      .run(state, error?.kind ?? null, error?.message ?? null, deviceId, jobId);
  }

  private mustGet(deviceId: string, jobId: string): StoredJob {
    const job = this.get(deviceId, jobId);
    if (!job) throw new Error(`job ${jobId} vanished inside a transaction`);
    return job;
  }

  private transaction<T>(work: () => T): T {
    this.db.exec("BEGIN IMMEDIATE");
    try {
      const result = work();
      this.db.exec("COMMIT");
      return result;
    } catch (error) {
      this.db.exec("ROLLBACK");
      throw error;
    }
  }
}
