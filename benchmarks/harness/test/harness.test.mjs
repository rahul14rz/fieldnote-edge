import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { Ajv } from "ajv";
import { afterEach, describe, expect, it } from "vitest";

import { combine } from "../src/hybrid.mjs";
import { runMacArm, streamCompletion } from "../src/mac-arm.mjs";
import { loadPromptSet } from "../src/prompt-set.mjs";

const root = join(import.meta.dirname, "..", "..", "..");
const valid = readFileSync(join(root, "packages/contracts/fixtures/meeting-summary.valid.json"), "utf8");
const servers = [];
afterEach(async () => Promise.all(servers.splice(0).map((s) => new Promise((r) => s.close(r)))));

/** A llama-server stand-in that streams `answer` in three chunks with usage at the end. */
async function sseServer(answer) {
  const requests = [];
  const server = createServer((req, res) => {
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => {
      requests.push(JSON.parse(body));
      res.writeHead(200, { "content-type": "text/event-stream" });
      const third = Math.ceil(answer.length / 3);
      for (const part of [answer.slice(0, third), answer.slice(third, 2 * third), answer.slice(2 * third)]) {
        res.write(`data: ${JSON.stringify({ choices: [{ delta: { content: part } }] })}\n\n`);
      }
      res.write(`data: ${JSON.stringify({ choices: [], usage: { prompt_tokens: 900, completion_tokens: 120 } })}\n\n`);
      res.end("data: [DONE]\n\n");
    });
  });
  servers.push(server);
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  return { url: `http://127.0.0.1:${server.address().port}/v1`, requests };
}

describe("mac-arm", () => {
  it("streams one greedy completion and measures it from the request", async () => {
    const server = await sseServer("abcdef");
    let t = 0;
    const now = () => (t += 100);

    const result = await streamCompletion({ url: server.url, model: "m", prompt: "p", maxOutputTokens: 64, now });

    expect(result.text).toBe("abcdef");
    expect(result.chunks).toBe(3);
    expect(result.promptTokens).toBe(900);
    expect(result.outputTokens).toBe(120);
    expect(result.timeToFirstTokenMs).toBe(100);
    expect(result.endToEndMs).toBe(400);
    expect(result.decodeTokensPerSecond).toBeCloseTo(119 / 0.2);
    expect(server.requests[0]).toMatchObject({ temperature: 0, top_k: 1, max_tokens: 64, stream: true });
  });

  it("writes a run record that matches the schema and that summarize_runs.py reads", async () => {
    const server = await sseServer(valid);

    const record = await runMacArm({ url: server.url, model: "gemma-4-12b", device: "MacBook Air M4", repetitions: 2, warmup: 1 });

    const schema = JSON.parse(readFileSync(join(root, "benchmarks/results/run-record.schema.json"), "utf8"));
    const validate = new Ajv({ strict: false }).compile(schema);
    expect(validate(record), JSON.stringify(validate.errors)).toBe(true);
    expect(record.runs).toHaveLength(1 + 2 * loadPromptSet().cases.length);
    expect(server.requests[1].messages[0].content).toContain("Transcript:\n");

    const dir = mkdtempSync(join(tmpdir(), "harness-"));
    writeFileSync(join(dir, "mac.json"), JSON.stringify(record));
    execFileSync("python3", ["summarize_runs.py", "--output", join(dir, "summary.json"), join(dir, "mac.json")], {
      cwd: join(root, "benchmarks/evaluation"),
    });
    const summary = JSON.parse(readFileSync(join(dir, "summary.json"), "utf8"));
    expect(summary.llm[0]).toMatchObject({ device: "MacBook Air M4", backend: "server", runs: 2, medianLoadMs: null });
  });
});

describe("hybrid", () => {
  const record = (device, runs) => ({ device: { label: device }, promptSetVersion: "v", runs });
  const run = (caseId, repetition, endToEndMs, output) => ({ caseId, repetition, warmup: false, endToEndMs, output });

  it("uses the phone when its output is valid and adds the Mac time when it escalates", () => {
    const phone = record("OnePlus 11R", [
      run("en-short", 1, 1000, valid),
      run("en-short", 2, 1100, "not json"),
      run("en-short", 3, 900, valid),
    ]);
    const mac = record("MacBook Air M4", [
      run("en-short", 1, 400, valid),
      run("en-short", 2, 500, valid),
      run("en-short", 3, 450, "Sure!"),
    ]);

    const rows = combine(phone, mac).rows;

    expect(rows.find((r) => r.arm === "phone-only")).toMatchObject({ medianEndToEndMs: 1000, validShare: 2 / 3 });
    expect(rows.find((r) => r.arm === "mac-only")).toMatchObject({ medianEndToEndMs: 450, validShare: 2 / 3 });
    // Hybrid: 1000 (phone ok), 1100+500 (escalated, Mac ok), 900 (phone ok).
    expect(rows.find((r) => r.arm === "hybrid")).toMatchObject({ medianEndToEndMs: 1000, validShare: 1, escalatedShare: 1 / 3 });
  });

  it("sends a case over the word limit straight to the Mac", () => {
    const phone = record("p", [run("en-long", 1, 5000, valid)]);
    const mac = record("m", [run("en-long", 1, 800, valid)]);

    const hybrid = combine(phone, mac, { maxWords: 10 }).rows.find((r) => r.arm === "hybrid");

    expect(hybrid).toMatchObject({ medianEndToEndMs: 800, escalatedShare: 1 });
  });

  it("refuses to combine runs of different prompt sets", () => {
    expect(() => combine({ ...record("p", []), promptSetVersion: "a" }, { ...record("m", []), promptSetVersion: "b" })).toThrow(
      "prompt set versions differ",
    );
  });
});
