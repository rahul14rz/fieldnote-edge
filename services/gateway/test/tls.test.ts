import { mkdtempSync, statSync } from "node:fs";
import { request as httpRequest } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { afterEach, describe, expect, it } from "vitest";

import { loadOrCreateIdentity } from "../src/tls/identity.js";
import { call, startGateway, stopAll } from "./helpers.js";

afterEach(stopAll);

describe("TLS", () => {
  it("is refused by a client pinned to a different certificate", async () => {
    const gateway = await startGateway();
    const impostor = await loadOrCreateIdentity(mkdtempSync(join(tmpdir(), "impostor-")));

    await expect(call(gateway.url, "GET", "/health", { pin: impostor })).rejects.toThrow();
  });

  it("does not answer plain HTTP", async () => {
    const gateway = await startGateway();
    const { port } = new URL(gateway.url);

    const outcome = await new Promise<string>((resolve) => {
      const req = httpRequest({ host: "127.0.0.1", port, path: "/health" }, (res) => {
        resolve(`status ${String(res.statusCode)}`);
      });
      req.on("error", () => {
        resolve("connection failed");
      });
      req.end();
    });

    expect(outcome).not.toBe("status 200");
  });

  it("keeps the same certificate across restarts and writes the key with mode 0600", async () => {
    const dir = mkdtempSync(join(tmpdir(), "identity-"));

    const first = await loadOrCreateIdentity(dir);
    const second = await loadOrCreateIdentity(dir);

    expect(second.fingerprint).toBe(first.fingerprint);
    expect(first.fingerprint).toMatch(/^[0-9a-f]{64}$/);
    expect(statSync(join(dir, "gateway-key.pem")).mode & 0o777).toBe(0o600);
  });
});
