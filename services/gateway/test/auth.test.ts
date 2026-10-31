import { afterEach, describe, expect, it } from "vitest";

import { PAIRING_FAILURE_LIMIT } from "../src/app.js";
import { clientProof, serverProof } from "../src/auth/proof.js";
import { ScriptedBackend, call, pairDevice, startGateway, stopAll } from "./helpers.js";

afterEach(stopAll);

const job = { jobId: "job-1", kind: "summarize", transcript: "Arun: hello", language: "en" };

describe("pairing", () => {
  it("redeems a code once, proves itself to the phone, and yields working session tokens", async () => {
    const gateway = await startGateway({ backend: new ScriptedBackend([]) });
    const { code } = gateway.auth.createPairingCode(gateway.tls.fingerprint);
    const proof = clientProof(code, gateway.tls.fingerprint);

    const paired = await call(gateway.url, "POST", "/v1/pairing", {
      body: { proof, deviceName: "OnePlus 11R" },
    });
    const reused = await call(gateway.url, "POST", "/v1/pairing", {
      body: { proof, deviceName: "Other" },
    });

    expect(paired.status).toBe(201);
    const body = paired.json as { deviceId: string; deviceSecret: string; serverProof: string };
    expect(body.deviceId).toMatch(/^dev_[0-9a-f]{32}$/);
    expect(body.serverProof).toBe(serverProof(code, gateway.tls.fingerprint));
    expect(reused.status).toBe(401);
    const session = await call(gateway.url, "POST", "/v1/sessions", {
      body: { deviceId: body.deviceId, deviceSecret: body.deviceSecret },
    });
    expect(session.status).toBe(201);
    expect(gateway.auth.devices().map((d) => d.name)).toEqual(["OnePlus 11R"]);
  });

  it("rejects a proof made over another certificate, as a man in the middle would send", async () => {
    const gateway = await startGateway();
    const { code } = gateway.auth.createPairingCode(gateway.tls.fingerprint);
    const attackerFingerprint = "ab".repeat(32);

    const relayed = await call(gateway.url, "POST", "/v1/pairing", {
      body: { proof: clientProof(code, attackerFingerprint), deviceName: "phone" },
    });

    expect(relayed.status).toBe(401);
    expect(gateway.auth.devices()).toEqual([]);
  });

  it("rejects an expired code", async () => {
    const gateway = await startGateway();
    const { code } = gateway.auth.createPairingCode(gateway.tls.fingerprint);
    gateway.clock.advance(5 * 60_000 + 1);

    const proof = clientProof(code, gateway.tls.fingerprint);
    expect(
      (await call(gateway.url, "POST", "/v1/pairing", { body: { proof, deviceName: "p" } })).status,
    ).toBe(401);
  });

  it("answers 429 after repeated wrong proofs, until the window passes", async () => {
    const gateway = await startGateway();
    const wrong = { proof: "0".repeat(64), deviceName: "attacker" };
    for (let i = 0; i < PAIRING_FAILURE_LIMIT; i++) {
      expect((await call(gateway.url, "POST", "/v1/pairing", { body: wrong })).status).toBe(401);
    }
    const { code } = gateway.auth.createPairingCode(gateway.tls.fingerprint);
    const proof = clientProof(code, gateway.tls.fingerprint);

    expect(
      (await call(gateway.url, "POST", "/v1/pairing", { body: { proof, deviceName: "p" } })).status,
    ).toBe(429);
    gateway.clock.advance(60_000);
    expect(
      (await call(gateway.url, "POST", "/v1/pairing", { body: { proof, deviceName: "p" } })).status,
    ).toBe(201);
  });

  it("generates codes of ten Crockford base32 characters that differ each time", async () => {
    const gateway = await startGateway();
    const codes = new Set(
      Array.from(
        { length: 50 },
        () => gateway.auth.createPairingCode(gateway.tls.fingerprint).code,
      ),
    );

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

    expect(missing).toMatchObject({
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
