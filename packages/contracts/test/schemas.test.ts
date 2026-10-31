import { readFileSync } from "node:fs";
import { join } from "node:path";

import { Ajv } from "ajv";
import { describe, expect, it } from "vitest";

import type { MeetingSummary } from "../generated/ts/index.ts";

const root = join(import.meta.dirname, "..");
const readJson = (path: string): unknown => JSON.parse(readFileSync(join(root, path), "utf8"));

const ajv = new Ajv({ allErrors: true, strict: true });
const validateSummary = ajv.compile(readJson("schema/meeting-summary.schema.json") as object);

describe("MeetingSummary schema", () => {
  it("accepts the shared valid fixture, which also type-checks as the generated type", () => {
    const summary = readJson("fixtures/meeting-summary.valid.json") as MeetingSummary;
    expect(validateSummary(summary), JSON.stringify(validateSummary.errors)).toBe(true);
    expect(summary.actionItems[1]?.owner).toBeNull();
  });

  it.each((readJson("fixtures/meeting-summary.invalid.json") as unknown[]).map((c, i) => [i, c]))(
    "rejects invalid fixture %i",
    (_index, candidate) => {
      expect(validateSummary(candidate)).toBe(false);
    },
  );
});

const validateSubmission = ajv.compile(readJson("schema/job-submission.schema.json") as object);
const validateStatus = ajv.compile(readJson("schema/job-status.schema.json") as object);

describe("JobSubmission schema", () => {
  const valid = { jobId: "job-1", kind: "summarize", transcript: "Arun: hello", language: "en" };

  it("accepts a summarize job, with or without a known language", () => {
    expect(validateSubmission(valid)).toBe(true);
    expect(validateSubmission({ ...valid, language: null })).toBe(true);
  });

  it.each([
    ["an unsafe job id", { ...valid, jobId: "../etc/passwd" }],
    ["an empty transcript", { ...valid, transcript: "" }],
    ["an unknown kind", { ...valid, kind: "transcribe" }],
    ["a missing language", { jobId: "j", kind: "summarize", transcript: "t" }],
  ])("rejects %s", (_name, body) => {
    expect(validateSubmission(body)).toBe(false);
  });
});

describe("JobStatus schema", () => {
  it("accepts a queued job and a failed job with its error kind", () => {
    expect(validateStatus({ jobId: "j", state: "queued", attempts: 0, error: null })).toBe(true);
    expect(
      validateStatus({
        jobId: "j",
        state: "failed",
        attempts: 1,
        error: { kind: "invalid_output", message: "not JSON" },
      }),
    ).toBe(true);
  });

  it("rejects an unknown error kind", () => {
    expect(
      validateStatus({ jobId: "j", state: "failed", attempts: 1, error: { kind: "oops", message: "" } }),
    ).toBe(false);
  });
});
