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
  job_id: string;
  request_hash: string;
  request: string;
  state: JobState;
  attempts: number;
  summary: string | null;
  error_kind: JobErrorKind | null;
  error_message: string | null;
}

function requestHash(submission: JobSubmission): string {
  const { kind, transcript, language } = submission;
  return createHash("sha256")
    .update(JSON.stringify([kind, transcript, language]))
    .digest("hex");
}

function toJob(row: Row): StoredJob {
  return {
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
 * Durable gateway jobs in SQLite. Every state change is one statement or one
 * transaction, so a crash never leaves a half-applied change.
 */
export class JobStore {
  private readonly db: DatabaseSync;

  constructor(path: string) {
    this.db = new DatabaseSync(path);
    this.db.exec(`
      PRAGMA journal_mode = WAL;
      CREATE TABLE IF NOT EXISTS jobs (
        job_id TEXT PRIMARY KEY,
        request_hash TEXT NOT NULL,
        request TEXT NOT NULL,
        state TEXT NOT NULL CHECK (state IN ('queued', 'processing', 'completed', 'failed')),
        attempts INTEGER NOT NULL DEFAULT 0,
        summary TEXT,
        error_kind TEXT CHECK (error_kind IN ('invalid_output', 'backend_error')),
        error_message TEXT,
        created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
        updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
      );
    `);
  }

  get(jobId: string): StoredJob | undefined {
    const row = this.db.prepare("SELECT * FROM jobs WHERE job_id = ?").get(jobId) as
      Row | undefined;
    return row && toJob(row);
  }

  /**
   * Idempotent on jobId. The same body returns the stored job; a job that
   * failed with backend_error is queued again, because that failure may go
   * away. A different body for an existing jobId is a conflict.
   */
  submit(submission: JobSubmission): SubmitResult {
    return this.transaction(() => {
      const existing = this.get(submission.jobId);
      const hash = requestHash(submission);
      if (!existing) {
        this.db
          .prepare(
            "INSERT INTO jobs (job_id, request_hash, request, state) VALUES (?, ?, ?, 'queued')",
          )
          .run(submission.jobId, hash, JSON.stringify(submission));
        return { outcome: "created", job: this.mustGet(submission.jobId) };
      }
      const row = this.db
        .prepare("SELECT request_hash FROM jobs WHERE job_id = ?")
        .get(submission.jobId) as { request_hash: string };
      if (row.request_hash !== hash) return { outcome: "conflict", job: existing };
      if (existing.status.state === "failed" && existing.status.error?.kind === "backend_error") {
        this.setState(submission.jobId, "queued", null);
        return { outcome: "requeued", job: this.mustGet(submission.jobId) };
      }
      return { outcome: "existing", job: existing };
    });
  }

  /** Moves the oldest queued job to processing and returns it. */
  claimNext(): StoredJob | undefined {
    return this.transaction(() => {
      const row = this.db
        .prepare(
          "SELECT job_id FROM jobs WHERE state = 'queued' ORDER BY created_at, rowid LIMIT 1",
        )
        .get() as { job_id: string } | undefined;
      if (!row) return undefined;
      this.db
        .prepare(
          "UPDATE jobs SET state = 'processing', attempts = attempts + 1, error_kind = NULL, error_message = NULL, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE job_id = ?",
        )
        .run(row.job_id);
      return this.mustGet(row.job_id);
    });
  }

  complete(jobId: string, summary: MeetingSummary): void {
    this.db
      .prepare(
        "UPDATE jobs SET state = 'completed', summary = ?, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE job_id = ? AND state = 'processing'",
      )
      .run(JSON.stringify(summary), jobId);
  }

  fail(jobId: string, kind: JobErrorKind, message: string): void {
    this.setState(jobId, "failed", { kind, message });
  }

  /** Jobs left processing by a crash go back to queued. Returns how many. */
  recoverInterrupted(): number {
    const result = this.db
      .prepare(
        "UPDATE jobs SET state = 'queued', updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE state = 'processing'",
      )
      .run();
    return Number(result.changes);
  }

  close(): void {
    this.db.close();
  }

  private setState(
    jobId: string,
    state: JobState,
    error: { kind: JobErrorKind; message: string } | null,
  ): void {
    this.db
      .prepare(
        "UPDATE jobs SET state = ?, error_kind = ?, error_message = ?, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE job_id = ?",
      )
      .run(state, error?.kind ?? null, error?.message ?? null, jobId);
  }

  private mustGet(jobId: string): StoredJob {
    const job = this.get(jobId);
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
