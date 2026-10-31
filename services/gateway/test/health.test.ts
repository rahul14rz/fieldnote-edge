import { afterEach, describe, expect, it } from "vitest";

import { call, startGateway, stopAll } from "./helpers.js";

afterEach(stopAll);

describe("GET /health", () => {
  it("answers 200 with the HealthResponse contract over pinned HTTPS", async () => {
    const { url } = await startGateway();

    const response = await call(url, "GET", "/health");

    expect(response.status).toBe(200);
    expect(response.json).toEqual({ status: "ok", service: "fieldnote-gateway", version: "0.0.0" });
  });

  it("echoes a caller's correlation id and logs every request line with it", async () => {
    const { url, logs } = await startGateway();

    const response = await call(url, "GET", "/health", { headers: { "x-request-id": "visit-42" } });

    expect(response.headers["x-request-id"]).toBe("visit-42");
    const requestLogs = logs.filter((line) => "req" in line || "res" in line);
    expect(requestLogs).toHaveLength(2);
    expect(requestLogs.every((line) => line.correlationId === "visit-42")).toBe(true);
  });

  it("issues a fresh UUID when the caller sends no id or an unsafe one", async () => {
    const { url } = await startGateway();
    const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

    const none = await call(url, "GET", "/health");
    const unsafe = await call(url, "GET", "/health", {
      headers: { "x-request-id": "<script>x</script>" },
    });
    const tooLong = await call(url, "GET", "/health", {
      headers: { "x-request-id": "a".repeat(65) },
    });

    expect(none.headers["x-request-id"]).toMatch(uuid);
    expect(unsafe.headers["x-request-id"]).toMatch(uuid);
    expect(tooLong.headers["x-request-id"]).toMatch(uuid);
    expect(unsafe.headers["x-request-id"]).not.toBe(none.headers["x-request-id"]);
  });

  it("returns 404 for routes that do not exist", async () => {
    const { url } = await startGateway();

    expect((await call(url, "GET", "/nope")).status).toBe(404);
  });
});
