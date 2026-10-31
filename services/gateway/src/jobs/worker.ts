import { readFileSync } from "node:fs";

import type { MeetingSummary } from "@fieldnote/contracts";
import meetingSummarySchema from "@fieldnote/contracts/schema/meeting-summary.schema.json" with { type: "json" };
import { Ajv } from "ajv";
import type { FastifyBaseLogger } from "fastify";

import type { InferenceBackend } from "./backend.js";
import type { JobStore } from "./store.js";

const promptTemplate = readFileSync(
  new URL(import.meta.resolve("@fieldnote/contracts/prompts/summarize.txt")),
  "utf8",
);
const schemaText = JSON.stringify(meetingSummarySchema, null, 2);
const validateSummary = new Ajv({ allErrors: true, strict: true }).compile<MeetingSummary>(
  meetingSummarySchema,
);

export function summarizePrompt(transcript: string): string {
  return promptTemplate.replace("{schema}", schemaText).replace("{transcript}", transcript);
}

/**
 * Parses a model answer into a MeetingSummary. One Markdown code fence around
 * the whole answer is accepted; any other text makes the answer invalid.
 */
export function parseSummary(
  answer: string,
): { ok: true; summary: MeetingSummary } | { ok: false; reason: string } {
  const fenced = /^\s*```(?:json)?\s*\n([\s\S]*?)\n```\s*$/.exec(answer);
  let value: unknown;
  try {
    value = JSON.parse(fenced?.[1] ?? answer);
  } catch {
    return { ok: false, reason: "the answer is not JSON" };
  }
  if (!validateSummary(value)) {
    const errors = (validateSummary.errors ?? []).map(
      (e) => `${e.instancePath || "/"} ${e.message ?? ""}`,
    );
    return { ok: false, reason: `the answer is not a valid MeetingSummary: ${errors.join("; ")}` };
  }
  return { ok: true, summary: value };
}

/**
 * Processes queued jobs one at a time. `kick()` starts draining the queue if
 * it is not already running; `idle()` resolves when the queue is empty.
 */
export class JobWorker {
  private running: Promise<void> | null = null;

  constructor(
    private readonly store: JobStore,
    private readonly backend: InferenceBackend,
    private readonly log: FastifyBaseLogger,
  ) {}

  kick(): void {
    this.running ??= this.drain().finally(() => {
      this.running = null;
    });
  }

  async idle(): Promise<void> {
    while (this.running) await this.running;
  }

  private async drain(): Promise<void> {
    for (let job = this.store.claimNext(); job; job = this.store.claimNext()) {
      const { jobId } = job.status;
      const log = this.log.child({ correlationId: jobId, attempt: job.status.attempts });
      let answer: string;
      try {
        answer = await this.backend.generate(summarizePrompt(job.submission.transcript));
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        log.warn({ err: message }, "inference backend failed");
        this.store.fail(jobId, "backend_error", message);
        continue;
      }
      const parsed = parseSummary(answer);
      if (parsed.ok) {
        this.store.complete(jobId, parsed.summary);
        log.info("job completed");
      } else {
        this.store.fail(jobId, "invalid_output", parsed.reason);
        log.info({ reason: parsed.reason }, "model output failed validation");
      }
    }
  }
}
