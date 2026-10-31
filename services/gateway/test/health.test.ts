import { afterEach, describe, expect, it } from "vitest";

import { startGateway, stopAll } from "./helpers.js";

afterEach(stopAll);

async function start(): Promise<{ url: string; logs: Record<string, unknown>[] }> {
  return startGateway();
}

describe("GET /health", () => {
  it("answers 200 with the HealthResponse contract over a real socket", async () => {
    const { url } = await start();

    const response = await fetch(`${url}/health`);

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      status: "ok",
      service: "fieldnote-gateway",
      version: "0.0.0",
    });
  });

  it("echoes a caller's correlation id and logs every request line with it", async () => {
    const { url, logs } = await start();

    const response = await fetch(`${url}/health`, { headers: { "x-request-id": "visit-42" } });

    expect(response.headers.get("x-request-id")).toBe("visit-42");
    const requestLogs = logs.filter((line) => "req" in line || "res" in line);
    expect(requestLogs).toHaveLength(2);
    expect(requestLogs.every((line) => line.correlationId === "visit-42")).toBe(true);
  });

  it("issues a fresh UUID when the caller sends no id or an unsafe one", async () => {
    const { url } = await start();
    const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

    const none = await fetch(`${url}/health`);
    const unsafe = await fetch(`${url}/health`, {
      headers: { "x-request-id": "<script>x</script>" },
    });
    const tooLong = await fetch(`${url}/health`, { headers: { "x-request-id": "a".repeat(65) } });

    expect(none.headers.get("x-request-id")).toMatch(uuid);
    expect(unsafe.headers.get("x-request-id")).toMatch(uuid);
    expect(tooLong.headers.get("x-request-id")).toMatch(uuid);
    expect(unsafe.headers.get("x-request-id")).not.toBe(none.headers.get("x-request-id"));
  });

  it("returns 404 for routes that do not exist yet", async () => {
    const { url } = await start();

    expect((await fetch(`${url}/jobs`)).status).toBe(404);
  });
});
