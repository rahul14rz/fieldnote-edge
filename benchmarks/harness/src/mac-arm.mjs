// Runs the spike's prompt set against an OpenAI-compatible model server on the
// Mac and writes a run record in the spike's format (run-record.schema.json).
//
// Usage: node src/mac-arm.mjs --url http://127.0.0.1:8080/v1 --model <name>
//          --device "MacBook Air M4" --repetitions 3 --warmup 1 --output <file>
import { writeFileSync } from "node:fs";
import { cpus, platform, release } from "node:os";
import { parseArgs } from "node:util";

import { loadPromptSet } from "./prompt-set.mjs";

/**
 * Streams one greedy chat completion. Returns timings measured from sending
 * the request, the full text, and the server's token counts when it reports them.
 */
export async function streamCompletion({ url, model, prompt, maxOutputTokens, now = () => performance.now() }) {
  const start = now();
  const response = await fetch(`${url.replace(/\/+$/, "")}/chat/completions`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      model,
      messages: [{ role: "user", content: prompt }],
      temperature: 0,
      top_k: 1,
      max_tokens: maxOutputTokens,
      stream: true,
      stream_options: { include_usage: true },
    }),
  });
  if (!response.ok || !response.body) throw new Error(`model server answered ${response.status}`);
  let text = "";
  let first = null;
  let last = null;
  let chunks = 0;
  let usage = null;
  let buffer = "";
  const decoder = new TextDecoder();
  for await (const bytes of response.body) {
    buffer += decoder.decode(bytes, { stream: true });
    let newline;
    while ((newline = buffer.indexOf("\n")) >= 0) {
      const line = buffer.slice(0, newline).trim();
      buffer = buffer.slice(newline + 1);
      if (!line.startsWith("data:")) continue;
      const data = line.slice(5).trim();
      if (data === "[DONE]") continue;
      const event = JSON.parse(data);
      if (event.usage) usage = event.usage;
      const delta = event.choices?.[0]?.delta?.content;
      if (typeof delta === "string" && delta.length > 0) {
        const at = now();
        first ??= at;
        last = at;
        chunks++;
        text += delta;
      }
    }
  }
  const end = now();
  const outputTokens = usage?.completion_tokens ?? null;
  const span = first === null ? null : last - first;
  return {
    text,
    promptTokens: usage?.prompt_tokens ?? null,
    timeToFirstTokenMs: first === null ? null : first - start,
    endToEndMs: end - start,
    firstToLastChunkMs: span,
    outputTokens,
    chunks,
    decodeTokensPerSecond:
      outputTokens !== null && outputTokens > 1 && span !== null && span > 0 ? (outputTokens - 1) / (span / 1000) : null,
  };
}

const noMemory = { anonymousBytes: null, fileBackedBytes: null, anonymousPeakBytes: null, maxRssBytes: null };
const noPeaks = {
  sampledMaxAnonymousBytes: null,
  sampledMaxFileBackedBytes: null,
  anonymousPeakBytes: null,
  maxRssBytes: null,
  samples: 0,
};

export async function runMacArm({ url, model, device, repetitions, warmup, now }) {
  const promptSet = loadPromptSet();
  const startedAt = new Date();
  const plan = [
    ...Array.from({ length: warmup }, (_, i) => [promptSet.cases[0], i + 1, true]),
    ...Array.from({ length: repetitions }, (_, r) => promptSet.cases.map((c) => [c, r + 1, false])).flat(),
  ];
  const runs = [];
  for (const [promptCase, repetition, isWarmup] of plan) {
    const result = await streamCompletion({ url, model, prompt: promptCase.prompt, maxOutputTokens: promptCase.maxOutputTokens, now });
    runs.push({
      caseId: promptCase.id,
      repetition,
      warmup: isWarmup,
      promptTokens: result.promptTokens ?? 0,
      timeToFirstTokenMs: result.timeToFirstTokenMs,
      endToEndMs: result.endToEndMs,
      firstToLastChunkMs: result.firstToLastChunkMs,
      outputTokens: result.outputTokens ?? 0,
      chunks: result.chunks,
      decodeTokensPerSecond: result.decodeTokensPerSecond,
      memory: noPeaks,
      output: result.text,
    });
  }
  const runId = `${startedAt.toISOString().replace(/[-:]/g, "").split(".")[0]}Z-mac-llm`;
  return {
    schemaVersion: 1,
    runId,
    startedAt: startedAt.toISOString(),
    finishedAt: new Date().toISOString(),
    device: { label: device, os: platform(), osVersion: release(), processors: cpus().length },
    packages: {},
    config: { mode: "llm", llm: { modelId: model, baseUrl: url, repetitions, warmupRuns: warmup } },
    model: { requestedBackend: "server", activeBackend: null, loadMs: null, memoryBeforeLoad: noMemory, memoryAfterLoad: noMemory },
    mode: "llm",
    promptSetVersion: promptSet.version,
    runs,
  };
}

if (process.argv[1] === import.meta.filename) {
  const { values } = parseArgs({
    options: {
      url: { type: "string" },
      model: { type: "string" },
      device: { type: "string", default: "MacBook Air M4" },
      repetitions: { type: "string", default: "3" },
      warmup: { type: "string", default: "1" },
      output: { type: "string" },
    },
  });
  if (!values.url || !values.model || !values.output) {
    console.error("usage: mac-arm.mjs --url <base url ending in /v1> --model <name> --output <file> [--device] [--repetitions] [--warmup]");
    process.exit(2);
  }
  const record = await runMacArm({
    url: values.url,
    model: values.model,
    device: values.device,
    repetitions: Number(values.repetitions),
    warmup: Number(values.warmup),
  });
  writeFileSync(values.output, JSON.stringify(record, null, 2) + "\n");
  console.log(`wrote ${values.output}: ${record.runs.length} runs`);
}
