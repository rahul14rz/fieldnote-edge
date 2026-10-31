import { mkdtempSync, rmSync } from "node:fs";
import type { AddressInfo } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { type App, buildApp } from "../src/app.js";
import type { InferenceBackend } from "../src/jobs/backend.js";
import { JobStore } from "../src/jobs/store.js";

export interface Gateway {
  url: string;
  app: App;
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
  const store = new JobStore(dbPath);
  const logs: Record<string, unknown>[] = [];
  const app = buildApp({
    env: { LOG_LEVEL: "info" },
    store,
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
  };
  cleanups.push(async () => {
    await stop();
    rmSync(dir, { recursive: true, force: true });
  });
  return { url: `http://127.0.0.1:${String(port)}`, app, logs, dbPath, stop };
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
