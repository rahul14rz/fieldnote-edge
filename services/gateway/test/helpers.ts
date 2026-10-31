import { mkdtempSync, rmSync } from "node:fs";
import { request } from "node:https";
import type { AddressInfo } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { type App, buildApp } from "../src/app.js";
import { clientProof } from "../src/auth/proof.js";
import { AuthStore } from "../src/auth/store.js";
import type { InferenceBackend } from "../src/jobs/backend.js";
import { JobStore } from "../src/jobs/store.js";
import { type TlsIdentity, loadOrCreateIdentity } from "../src/tls/identity.js";

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
  tls: TlsIdentity;
  stop(): Promise<void>;
}

const cleanups: (() => Promise<void>)[] = [];

export async function stopAll(): Promise<void> {
  await Promise.all(cleanups.splice(0).map((c) => c()));
}

/** Starts a real gateway on port 0 with a fresh SQLite file. */
export async function startGateway(
  options: { backend?: InferenceBackend; dbPath?: string; tlsDir?: string } = {},
): Promise<Gateway> {
  const dir = mkdtempSync(join(tmpdir(), "gateway-"));
  const dbPath = options.dbPath ?? join(dir, "gateway.sqlite");
  const tls = await loadOrCreateIdentity(options.tlsDir ?? join(dir, "tls"));
  const clock = new TestClock();
  const store = new JobStore(dbPath);
  const auth = new AuthStore(dbPath, clock.now);
  const logs: Record<string, unknown>[] = [];
  const app = buildApp({
    env: { LOG_LEVEL: "info" },
    store,
    auth,
    now: clock.now,
    tls,
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
  lastIdentity.set(`https://127.0.0.1:${String(port)}`, tls);
  cleanups.push(async () => {
    await stop();
    rmSync(dir, { recursive: true, force: true });
  });
  return { url: `https://127.0.0.1:${String(port)}`, app, auth, clock, logs, dbPath, tls, stop };
}

/**
 * An HTTPS request pinned to one certificate, as the phone makes it: the
 * pinned certificate is the only trusted CA, and the fingerprint must match.
 */
export function call(
  url: string,
  method: string,
  path: string,
  options: {
    body?: unknown;
    token?: string;
    pin?: TlsIdentity;
    headers?: Record<string, string>;
  } = {},
): Promise<{
  status: number;
  json: unknown;
  headers: Record<string, string | string[] | undefined>;
}> {
  const pin = options.pin ?? lastIdentity.get(url);
  if (!pin) throw new Error(`no pinned certificate for ${url}`);
  const { hostname, port } = new URL(url);
  const headers: Record<string, string> = { ...options.headers };
  const body = options.body === undefined ? undefined : JSON.stringify(options.body);
  if (body !== undefined) headers["content-type"] = "application/json";
  if (options.token !== undefined) headers.authorization = `Bearer ${options.token}`;
  return new Promise((resolve, reject) => {
    const req = request(
      {
        hostname,
        port,
        path,
        method,
        headers,
        ca: pin.cert,
        checkServerIdentity: (_host, cert) =>
          cert.fingerprint256.replaceAll(":", "").toLowerCase() === pin.fingerprint
            ? undefined
            : new Error("certificate fingerprint does not match the pin"),
      },
      (res) => {
        let text = "";
        res.setEncoding("utf8");
        res.on("data", (chunk: string) => (text += chunk));
        res.on("end", () => {
          resolve({
            status: res.statusCode ?? 0,
            json: text === "" ? null : (JSON.parse(text) as unknown),
            headers: res.headers,
          });
        });
      },
    );
    req.on("error", reject);
    req.end(body);
  });
}

const lastIdentity = new Map<string, TlsIdentity>();

/** Pairs a device through the HTTP API and returns its credential and a session token. */
export async function pairDevice(
  gateway: Gateway,
  name = "OnePlus 11R",
): Promise<{ deviceId: string; deviceSecret: string; token: string }> {
  const { code } = gateway.auth.createPairingCode(gateway.tls.fingerprint);
  const proof = clientProof(code, gateway.tls.fingerprint);
  const paired = await call(gateway.url, "POST", "/v1/pairing", {
    body: { proof, deviceName: name },
  });
  const { deviceId, deviceSecret } = paired.json as { deviceId: string; deviceSecret: string };
  const credential = { deviceId, deviceSecret };
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
