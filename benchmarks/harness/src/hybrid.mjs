// Combines a phone run record and a Mac run record of the same prompt set into
// three execution arms per prompt case: phone only, Mac only, and hybrid.
//
// Hybrid follows the routing rules for summary jobs (ADR 0007): run on the
// phone; if the phone output is invalid, run on the Mac as well. With
// --max-words, a case whose transcript is over the limit goes to the Mac
// directly. Network transfer to the Mac is not included in the Mac times.
//
// Usage: node src/hybrid.mjs --phone <run.json> --mac <run.json> [--max-words N] --output <file>
import { readFileSync, writeFileSync } from "node:fs";
import { parseArgs } from "node:util";

import { checkOutput } from "../../../packages/contracts/scripts/validate-outputs.mjs";
import { loadPromptSet } from "./prompt-set.mjs";

const median = (values) => {
  const sorted = values.filter((v) => v !== null).sort((a, b) => a - b);
  if (sorted.length === 0) return null;
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
};

function byCase(record) {
  const map = new Map();
  for (const run of record.runs) {
    if (run.warmup) continue;
    const list = map.get(run.caseId) ?? [];
    list.push({ endToEndMs: run.endToEndMs, valid: checkOutput(run.output).valid, repetition: run.repetition });
    map.set(run.caseId, list.sort((a, b) => a.repetition - b.repetition));
  }
  return map;
}

export function combine(phoneRecord, macRecord, { maxWords = null } = {}) {
  if (phoneRecord.promptSetVersion !== macRecord.promptSetVersion) {
    throw new Error(`prompt set versions differ: ${phoneRecord.promptSetVersion} vs ${macRecord.promptSetVersion}`);
  }
  const words = new Map(loadPromptSet().cases.map((c) => [c.id, c.transcriptWords]));
  const phone = byCase(phoneRecord);
  const mac = byCase(macRecord);
  const rows = [];
  for (const [caseId, phoneRuns] of phone) {
    const macRuns = mac.get(caseId) ?? [];
    const pairs = phoneRuns.slice(0, macRuns.length).map((p, i) => [p, macRuns[i]]);
    const oversize = maxWords !== null && (words.get(caseId) ?? 0) > maxWords;
    const hybrid = pairs.map(([p, m]) => {
      if (oversize) return { endToEndMs: m.endToEndMs, valid: m.valid, escalated: true };
      if (p.valid) return { endToEndMs: p.endToEndMs, valid: true, escalated: false };
      return { endToEndMs: p.endToEndMs + m.endToEndMs, valid: m.valid, escalated: true };
    });
    const arm = (name, runs) => ({
      arm: name,
      caseId,
      runs: runs.length,
      medianEndToEndMs: median(runs.map((r) => r.endToEndMs)),
      validShare: runs.length === 0 ? null : runs.filter((r) => r.valid).length / runs.length,
    });
    rows.push(arm("phone-only", phoneRuns), arm("mac-only", macRuns), {
      ...arm("hybrid", hybrid),
      escalatedShare: hybrid.length === 0 ? null : hybrid.filter((r) => r.escalated).length / hybrid.length,
    });
  }
  return {
    promptSetVersion: phoneRecord.promptSetVersion,
    phoneDevice: phoneRecord.device.label,
    macDevice: macRecord.device.label,
    maxWords,
    rows,
  };
}

if (process.argv[1] === import.meta.filename) {
  const { values } = parseArgs({
    options: { phone: { type: "string" }, mac: { type: "string" }, "max-words": { type: "string" }, output: { type: "string" } },
  });
  if (!values.phone || !values.mac || !values.output) {
    console.error("usage: hybrid.mjs --phone <run.json> --mac <run.json> [--max-words N] --output <file>");
    process.exit(2);
  }
  const result = combine(JSON.parse(readFileSync(values.phone, "utf8")), JSON.parse(readFileSync(values.mac, "utf8")), {
    maxWords: values["max-words"] === undefined ? null : Number(values["max-words"]),
  });
  writeFileSync(values.output, JSON.stringify(result, null, 2) + "\n");
  for (const r of result.rows) {
    console.log(`${r.caseId}\t${r.arm}\truns=${r.runs}\tmedian=${r.medianEndToEndMs}ms\tvalid=${r.validShare}`);
  }
}
