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
