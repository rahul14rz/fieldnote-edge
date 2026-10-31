import { readFileSync } from "node:fs";
import { join } from "node:path";

import { describe, expect, it } from "vitest";

// @ts-expect-error -- plain ESM script without type declarations
import { checkOutput } from "../scripts/validate-outputs.mjs";

const valid = readFileSync(join(import.meta.dirname, "..", "fixtures", "meeting-summary.valid.json"), "utf8");
const check = checkOutput as (output: string) => { valid: boolean; reason: string | null };

describe("checkOutput", () => {
  it("accepts a bare JSON summary and one wrapped in a single code fence", () => {
    expect(check(valid).valid).toBe(true);
    expect(check("```json\n" + valid.trim() + "\n```").valid).toBe(true);
  });

  it("rejects prose around the JSON, non-JSON, and JSON that breaks the schema", () => {
    expect(check("Here is the summary:\n" + valid).valid).toBe(false);
    expect(check("not json").reason).toBe("not JSON");
    expect(check('{"participants": []}').valid).toBe(false);
  });
});
