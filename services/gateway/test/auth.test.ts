import { afterEach, describe, expect, it } from "vitest";

import { PAIRING_FAILURE_LIMIT } from "../src/app.js";
import { ScriptedBackend, call, pairDevice, startGateway, stopAll } from "./helpers.js";

afterEach(stopAll);

const job = { jobId: "job-1", kind: "summarize", transcript: "Arun: hello", language: "en" };

describe("pairing", () => {
  it("redeems a code once for a device credential that yields working session tokens", async () => {
    const gateway = await startGateway({ backend: new ScriptedBackend([]) });
    const { code } = gateway.auth.createPairingCode();

    const paired = await call(gateway.url, "POST", "/v1/pairing", {
      body: { code, deviceName: "OnePlus 11R" },
    });
    const reused = await call(gateway.url, "POST", "/v1/pairing", {
      body: { code, deviceName: "Other" },
    });

    expect(paired.status).toBe(201);
    expect(paired.json).toMatchObject({
      deviceId: expect.stringMatching(/^dev_[0-9a-f]{32}$/) as unknown,
    });
    expect(reused.status).toBe(401);
    const session = await call(gateway.url, "POST", "/v1/sessions", { body: paired.json });
    expect(session.status).toBe(201);
    expect(gateway.auth.devices().map((d) => d.name)).toEqual(["OnePlus 11R"]);
  });

  it("rejects an expired code", async () => {
    const gateway = await startGateway();
    const { code } = gateway.auth.createPairingCode();
    gateway.clock.advance(5 * 60_000 + 1);

    expect(
      (await call(gateway.url, "POST", "/v1/pairing", { body: { code, deviceName: "p" } })).status,
    ).toBe(401);
  });

  it("answers 429 after repeated wrong codes, until the window passes", async () => {
    const gateway = await startGateway();
    const wrong = { code: "0000000000", deviceName: "attacker" };
    for (let i = 0; i < PAIRING_FAILURE_LIMIT; i++) {
      expect((await call(gateway.url, "POST", "/v1/pairing", { body: wrong })).status).toBe(401);
    }
    const { code } = gateway.auth.createPairingCode();

    expect(
      (await call(gateway.url, "POST", "/v1/pairing", { body: { code, deviceName: "p" } })).status,
    ).toBe(429);
    gateway.clock.advance(60_000);
    expect(
      (await call(gateway.url, "POST", "/v1/pairing", { body: { code, deviceName: "p" } })).status,
    ).toBe(201);
  });

  it("generates codes of ten Crockford base32 characters that differ each time", async () => {
    const gateway = await startGateway();
    const codes = new Set(Array.from({ length: 50 }, () => gateway.auth.createPairingCode().code));

    expect(codes.size).toBe(50);
    for (const code of codes) expect(code).toMatch(/^[0-9A-HJKMNP-TV-Z]{10}$/);
  });
});

describe("sessions", () => {
  it("rejects a wrong device secret", async () => {
    const gateway = await startGateway();
    const device = await pairDevice(gateway);
    const wrongSecret = "A".repeat(43);

    expect(
      (
        await call(gateway.url, "POST", "/v1/sessions", {
          body: { deviceId: device.deviceId, deviceSecret: wrongSecret },
        })
      ).status,
    ).toBe(401);
  });

  it("expires a session token after 15 minutes", async () => {
    const gateway = await startGateway({ backend: new ScriptedBackend([]) });
    const { token } = await pairDevice(gateway);

    expect((await call(gateway.url, "GET", "/v1/jobs/none", { token })).status).toBe(404);
    gateway.clock.advance(15 * 60_000);
    expect((await call(gateway.url, "GET", "/v1/jobs/none", { token })).status).toBe(401);
  });
});

describe("job endpoints", () => {
  it("require a session token", async () => {
    const gateway = await startGateway({ backend: new ScriptedBackend([]) });

    const missing = await call(gateway.url, "POST", "/v1/jobs", { body: job });
    const forged = await call(gateway.url, "GET", "/v1/jobs/job-1", { token: "A".repeat(43) });

    expect(missing).toEqual({
      status: 401,
      json: { message: "a valid session token is required" },
    });
    expect(forged.status).toBe(401);
  });

  it("show a device only its own jobs", async () => {
    const gateway = await startGateway({ backend: new ScriptedBackend([]) });
    const phone = await pairDevice(gateway, "phone");
    const other = await pairDevice(gateway, "other");

    await call(gateway.url, "POST", "/v1/jobs", { body: job, token: phone.token });

    expect((await call(gateway.url, "GET", "/v1/jobs/job-1", { token: phone.token })).status).toBe(
      200,
    );
    expect((await call(gateway.url, "GET", "/v1/jobs/job-1", { token: other.token })).status).toBe(
      404,
    );
  });
});

describe("revocation", () => {
  it("ends a device's sessions at once and stops it getting new ones", async () => {
    const gateway = await startGateway({ backend: new ScriptedBackend([]) });
    const device = await pairDevice(gateway);

    expect(gateway.auth.revoke(device.deviceId)).toBe(true);

    expect((await call(gateway.url, "GET", "/v1/jobs/x", { token: device.token })).status).toBe(
      401,
    );
    expect(
      (
        await call(gateway.url, "POST", "/v1/sessions", {
          body: { deviceId: device.deviceId, deviceSecret: device.deviceSecret },
        })
      ).status,
    ).toBe(401);
    expect(gateway.auth.devices()[0]?.revokedAt).not.toBeNull();
  });
});
