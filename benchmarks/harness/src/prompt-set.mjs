import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";

const root = resolve(import.meta.dirname, "..", "..", "..");

/** The spike's fixed prompt set, filled exactly as apps/spike fills it. */
export function loadPromptSet() {
  const set = JSON.parse(readFileSync(join(root, "apps/spike/assets/prompt_set.json"), "utf8"));
  const schema = readFileSync(join(root, "apps/spike/assets/meeting-summary.schema.json"), "utf8");
  return {
    version: set.version,
    cases: set.cases.map((c) => {
      const transcript = c.transcriptParts.map((part) => set.transcripts[part]).join("\n");
      return {
        id: c.id,
        maxOutputTokens: c.maxOutputTokens,
        transcriptWords: transcript.split(/\s+/).filter(Boolean).length,
        prompt: set.template.replaceAll("{schema}", schema).replaceAll("{transcript}", transcript),
      };
    }),
  };
}
