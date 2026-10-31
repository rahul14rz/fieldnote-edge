import { createServer, type IncomingMessage, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { readFileSync } from "node:fs";

import { afterEach, describe, expect, it } from "vitest";

import { parseEnv } from "../src/env.js";
import { OpenAiCompatibleBackend } from "../src/jobs/openai-compatible.js";
import { advertisement } from "../src/mdns.js";
import { backendFor, shouldAdvertise } from "../src/server.js";
import { call, pairDevice, startGateway, stopAll } from "./helpers.js";

const servers: Server[] = [];
afterEach(async () => {
  await stopAll();
  await Promise.all(servers.splice(0).map((s) => new Promise((r) => s.close(r))));
});

const validSummary = readFileSync(
  new URL("../../../packages/contracts/fixtures/meeting-summary.valid.json", import.meta.url),
  "utf8",
);

/** A stand-in for llama-server: records requests and answers with `reply`. */
async function fakeModelServer(
  reply: (body: Record<string, unknown>) => { status: number; body: unknown },
): Promise<{ baseUrl: string; requests: Record<string, unknown>[] }> {
  const requests: Record<string, unknown>[] = [];
  const server = createServer((req: IncomingMessage, res) => {
    let text = "";
    req.on("data", (chunk: Buffer) => (text += chunk.toString()));
    req.on("end", () => {
      const body = JSON.parse(text) as Record<string, unknown>;
      requests.push({ path: req.url, ...body });
      const answer = reply(body);
      res.writeHead(answer.status, { "content-type": "application/json" });
      res.end(JSON.stringify(answer.body));
    });
  });
  servers.push(server);
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address() as AddressInfo;
  return { baseUrl: `http://127.0.0.1:${String(port)}/v1`, requests };
}

const options = (baseUrl: string) => ({
  baseUrl,
  model: "gemma-4-12b-it",
  timeoutMs: 2000,
  maxOutputTokens: 2048,
});

describe("OpenAiCompatibleBackend", () => {
  it("sends one greedy chat completion and returns the message content", async () => {
    const model = await fakeModelServer(() => ({
      status: 200,
      body: { choices: [{ message: { role: "assistant", content: "hello" } }] },
    }));

    const answer = await new OpenAiCompatibleBackend(options(model.baseUrl)).generate("the prompt");

    expect(answer).toBe("hello");
    expect(model.requests).toEqual([
      {
        path: "/v1/chat/completions",
        model: "gemma-4-12b-it",
        messages: [{ role: "user", content: "the prompt" }],
        temperature: 0,
        top_k: 1,
        max_tokens: 2048,
        stream: false,
      },
    ]);
  });

  it("throws on an HTTP error, a malformed body, or an unreachable server", async () => {
    const failing = await fakeModelServer(() => ({
      status: 500,
      body: { error: "out of memory" },
    }));
    const malformed = await fakeModelServer(() => ({ status: 200, body: { choices: [] } }));

    await expect(
      new OpenAiCompatibleBackend(options(failing.baseUrl)).generate("p"),
    ).rejects.toThrow("model server answered 500");
    await expect(
      new OpenAiCompatibleBackend(options(malformed.baseUrl)).generate("p"),
    ).rejects.toThrow("no message content");
    await expect(
      new OpenAiCompatibleBackend(options("http://127.0.0.1:1/v1")).generate("p"),
    ).rejects.toThrow("model server request failed");
  });

  it("drives a gateway job to completed end to end", async () => {
    const model = await fakeModelServer(() => ({
      status: 200,
      body: { choices: [{ message: { content: validSummary } }] },
    }));
    const gateway = await startGateway({
      backend: new OpenAiCompatibleBackend(options(model.baseUrl)),
    });
    const { token } = await pairDevice(gateway);

    await call(gateway.url, "POST", "/v1/jobs", {
      body: { jobId: "j1", kind: "summarize", transcript: "Arun: send it Friday", language: "en" },
      token,
    });
    await gateway.app.idle();

    expect((await call(gateway.url, "GET", "/v1/jobs/j1/summary", { token })).json).toEqual(
      JSON.parse(validSummary),
    );
  });
});

describe("configuration", () => {
  it("requires a URL and model for the openai-compatible backend", () => {
    expect(() => parseEnv({ INFERENCE_BACKEND: "openai-compatible" })).toThrow("INFERENCE_URL");
    const env = parseEnv({
      INFERENCE_BACKEND: "openai-compatible",
      INFERENCE_URL: "http://127.0.0.1:8080/v1",
      INFERENCE_MODEL: "gemma-4-12b-it",
    });
    expect(backendFor(env)?.name).toBe("openai-compatible");
    expect(backendFor(parseEnv({}))).toBeUndefined();
  });

  it("advertises over mDNS only beyond loopback unless told otherwise", () => {
    expect(shouldAdvertise({ MDNS: "auto", HOST: "127.0.0.1" })).toBe(false);
    expect(shouldAdvertise({ MDNS: "auto", HOST: "0.0.0.0" })).toBe(true);
    expect(shouldAdvertise({ MDNS: "off", HOST: "0.0.0.0" })).toBe(false);
    expect(shouldAdvertise({ MDNS: "on", HOST: "127.0.0.1" })).toBe(true);
  });

  it("advertises the port and the start of the fingerprint, nothing secret", () => {
    expect(advertisement(8787, "ab".repeat(32), "macbook")).toEqual({
      name: "Fieldnote gateway on macbook",
      type: "fieldnote",
      port: 8787,
      txt: { v: "1", fp: "abababababababab" },
    });
  });
});
