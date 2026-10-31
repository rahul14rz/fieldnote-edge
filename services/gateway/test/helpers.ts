import { mkdtempSync, rmSync } from "node:fs";
import type { AddressInfo } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { type App, buildApp } from "../src/app.js";
import { AuthStore } from "../src/auth/store.js";
import type { InferenceBackend } from "../src/jobs/backend.js";
import { JobStore } from "../src/jobs/store.js";

/** A clock the test moves by hand. */
export class TestClock {
  private ms = Date.parse("2026-11-01T09:00:00Z");
  now = (): Date => new Date(this.ms);
  advance(ms: number): void {
    this.ms += ms;
  }
}

export interface Gateway {
  url: string;
  app: App;
  auth: AuthStore;
  clock: TestClock;
  logs: Record<string, unknown>[];
  dbPath: string;
  stop(): Promise<void>;
}

const cleanups: (() => Promise<void>)[] = [];

export async function stopAll(): Promise<void> {
  await Promise.all(cleanups.splice(0).map((c) => c()));
}

/** Starts a real gateway on port 0 with a fresh SQLite file. */
export async function startGateway(
  options: { backend?: InferenceBackend; dbPath?: string } = {},
): Promise<Gateway> {
  const dir = mkdtempSync(join(tmpdir(), "gateway-"));
  const dbPath = options.dbPath ?? join(dir, "gateway.sqlite");
  const clock = new TestClock();
  const store = new JobStore(dbPath);
  const auth = new AuthStore(dbPath, clock.now);
  const logs: Record<string, unknown>[] = [];
  const app = buildApp({
    env: { LOG_LEVEL: "info" },
    store,
    auth,
    now: clock.now,
    ...(options.backend ? { backend: options.backend } : {}),
    logStream: { write: (line) => void logs.push(JSON.parse(line) as Record<string, unknown>) },
  });
  await app.server.listen({ host: "127.0.0.1", port: 0 });
  const { port } = app.server.server.address() as AddressInfo;
  let stopped = false;
  const stop = async () => {
    if (stopped) return;
    stopped = true;
    await app.server.close();
    store.close();
    auth.close();
  };
  cleanups.push(async () => {
    await stop();
    rmSync(dir, { recursive: true, force: true });
  });
  return { url: `http://127.0.0.1:${String(port)}`, app, auth, clock, logs, dbPath, stop };
}

export async function call(
  url: string,
  method: string,
  path: string,
  options: { body?: unknown; token?: string } = {},
): Promise<{ status: number; json: unknown }> {
  const headers: Record<string, string> = {};
  if (options.body !== undefined) headers["content-type"] = "application/json";
  if (options.token !== undefined) headers.authorization = `Bearer ${options.token}`;
  const response = await fetch(`${url}${path}`, {
    method,
    headers,
    ...(options.body !== undefined ? { body: JSON.stringify(options.body) } : {}),
  });
  return { status: response.status, json: await response.json() };
}

/** Pairs a device through the HTTP API and returns its credential and a session token. */
export async function pairDevice(
  gateway: Gateway,
  name = "OnePlus 11R",
): Promise<{ deviceId: string; deviceSecret: string; token: string }> {
  const { code } = gateway.auth.createPairingCode();
  const paired = await call(gateway.url, "POST", "/v1/pairing", {
    body: { code, deviceName: name },
  });
  const credential = paired.json as { deviceId: string; deviceSecret: string };
  const session = await call(gateway.url, "POST", "/v1/sessions", { body: credential });
  return { ...credential, token: (session.json as { sessionToken: string }).sessionToken };
}

/** A backend that answers from a queue of scripted results. */
export class ScriptedBackend implements InferenceBackend {
  readonly name = "scripted";
  readonly prompts: string[] = [];

  constructor(private readonly answers: (string | Error)[]) {}

  generate(prompt: string): Promise<string> {
    this.prompts.push(prompt);
    const next = this.answers.shift();
    if (next === undefined) return Promise.reject(new Error("no scripted answer left"));
    return next instanceof Error ? Promise.reject(next) : Promise.resolve(next);
  }
}
