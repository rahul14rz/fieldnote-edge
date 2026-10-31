// Reports how many LLM outputs in spike run records are valid MeetingSummary JSON.
// Usage: node scripts/validate-outputs.mjs <run.json>...
import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";

import { Ajv } from "ajv";

const root = resolve(import.meta.dirname, "..");
const schema = JSON.parse(readFileSync(join(root, "schema", "meeting-summary.schema.json"), "utf8"));
const validate = new Ajv({ allErrors: true, strict: true }).compile(schema);

// Models often wrap JSON in a Markdown code fence. Accept one fence around the
// whole output and nothing else, so prose around the JSON still counts as invalid.
export function parseOutput(output) {
  const fenced = /^\s*```(?:json)?\s*\n([\s\S]*?)\n```\s*$/.exec(output);
  return JSON.parse(fenced ? fenced[1] : output);
}

export function checkOutput(output) {
  let value;
  try {
    value = parseOutput(output);
  } catch {
    return { valid: false, reason: "not JSON" };
  }
  return validate(value)
    ? { valid: true, reason: null }
    : { valid: false, reason: validate.errors.map((e) => `${e.instancePath || "/"} ${e.message}`).join("; ") };
}

if (process.argv[1] === import.meta.filename) {
  const rows = [];
  for (const file of process.argv.slice(2)) {
    const record = JSON.parse(readFileSync(file, "utf8"));
    for (const run of record.runs ?? []) {
      if (run.warmup) continue;
      rows.push({ file, caseId: run.caseId, repetition: run.repetition, ...checkOutput(run.output) });
    }
  }
  for (const row of rows) {
    console.log(`${row.valid ? "valid  " : "INVALID"} ${row.caseId} #${row.repetition}${row.reason ? `: ${row.reason}` : ""}`);
  }
  console.log(`${rows.filter((r) => r.valid).length}/${rows.length} outputs are valid MeetingSummary JSON`);
}
