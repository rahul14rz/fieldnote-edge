import { readFileSync } from "node:fs";

import { afterEach, describe, expect, it } from "vitest";

import {
  type Gateway,
  ScriptedBackend,
  call,
  pairDevice,
  startGateway,
  stopAll,
} from "./helpers.js";

afterEach(stopAll);

const validSummary = readFileSync(
  new URL("../../../packages/contracts/fixtures/meeting-summary.valid.json", import.meta.url),
  "utf8",
);
const submission = (jobId = "job-1", transcript = "Arun: I will send the quote by Friday.") => ({
  jobId,
  kind: "summarize",
  transcript,
  language: "en",
});

let token = "";

async function start(options: Parameters<typeof startGateway>[0] = {}): Promise<Gateway> {
  const gateway = await startGateway(options);
  token = (await pairDevice(gateway)).token;
  return gateway;
}

const post = (url: string, body: unknown) => call(url, "POST", "/v1/jobs", { body, token });
const get = (url: string, path: string) => call(url, "GET", path, { token });

describe("POST /v1/jobs", () => {
  it("accepts a job, runs it, and serves the validated summary", async () => {
    const backend = new ScriptedBackend([validSummary]);
    const { url, app } = await start({ backend });

    const submitted = await post(url, submission());
    await app.idle();

    expect(submitted).toMatchObject({
      status: 202,
      json: { jobId: "job-1", state: "queued", attempts: 0, error: null },
    });
    expect((await get(url, "/v1/jobs/job-1")).json).toMatchObject({
      state: "completed",
      attempts: 1,
    });
    expect((await get(url, "/v1/jobs/job-1/summary")).json).toEqual(JSON.parse(validSummary));
    expect(backend.prompts[0]).toContain("Arun: I will send the quote by Friday.");
    expect(backend.prompts[0]).toContain('"title": "MeetingSummary"');
  });

  it("accepts a summary wrapped in one code fence", async () => {
    const { url, app } = await start({
      backend: new ScriptedBackend(["```json\n" + validSummary.trim() + "\n```"]),
    });

    await post(url, submission());
    await app.idle();

    expect((await get(url, "/v1/jobs/job-1")).json).toMatchObject({ state: "completed" });
  });

  it("fails the job as invalid_output when the model answer is not a valid summary", async () => {
    const { url, app } = await start({
      backend: new ScriptedBackend(['Sure! {"participants": []}']),
    });

    await post(url, submission());
    await app.idle();

    expect((await get(url, "/v1/jobs/job-1")).json).toMatchObject({
      state: "failed",
      error: { kind: "invalid_output", message: "the answer is not JSON" },
    });
    expect(await get(url, "/v1/jobs/job-1/summary")).toMatchObject({
      status: 409,
      json: { message: "job is failed, not completed" },
    });
  });

  it("is idempotent: the same body twice runs the model once", async () => {
    const backend = new ScriptedBackend([validSummary]);
    const { url, app } = await start({ backend });

    await post(url, submission());
    await app.idle();
    const again = await post(url, submission());

    expect(again.status).toBe(200);
    expect(again.json).toMatchObject({ state: "completed", attempts: 1 });
    expect(backend.prompts).toHaveLength(1);
  });

  it("does not rerun an invalid_output job on resubmit, because the answer would not change", async () => {
    const backend = new ScriptedBackend(["not json", validSummary]);
    const { url, app } = await start({ backend });

    await post(url, submission());
    await app.idle();
    const again = await post(url, submission());
    await app.idle();

    expect(again.json).toMatchObject({ state: "failed", error: { kind: "invalid_output" } });
    expect(backend.prompts).toHaveLength(1);
  });

  it("requeues a backend_error job on resubmit and counts the attempt", async () => {
    const backend = new ScriptedBackend([new Error("model server unreachable"), validSummary]);
    const { url, app } = await start({ backend });

    await post(url, submission());
    await app.idle();
    expect((await get(url, "/v1/jobs/job-1")).json).toMatchObject({
      state: "failed",
      error: { kind: "backend_error", message: "model server unreachable" },
    });

    expect((await post(url, submission())).status).toBe(202);
    await app.idle();

    expect((await get(url, "/v1/jobs/job-1")).json).toMatchObject({
      state: "completed",
      attempts: 2,
    });
  });

  it("rejects a different body under an existing job id with 409", async () => {
    const { url, app } = await start({ backend: new ScriptedBackend([validSummary]) });

    await post(url, submission("job-1", "first"));
    await app.idle();

    expect((await post(url, submission("job-1", "second"))).status).toBe(409);
  });

  it("rejects a body that breaks the JobSubmission contract with 400", async () => {
    const { url } = await start({ backend: new ScriptedBackend([]) });

    expect((await post(url, { ...submission(), jobId: "../x" })).status).toBe(400);
    expect((await post(url, { ...submission(), kind: "transcribe" })).status).toBe(400);
  });

  it("refuses jobs with 503 when no inference backend is configured", async () => {
    const { url } = await start();

    expect(await post(url, submission())).toMatchObject({
      status: 503,
      json: { message: "no inference backend is configured on the gateway" },
    });
  });

  it("answers 404 for an unknown job", async () => {
    const { url } = await start({ backend: new ScriptedBackend([]) });

    expect((await get(url, "/v1/jobs/nope")).status).toBe(404);
    expect((await get(url, "/v1/jobs/nope/summary")).status).toBe(404);
  });
});

describe("restart", () => {
  it("keeps completed jobs and reruns a job a crash left processing", async () => {
    // A backend that never answers keeps the job in processing, like a crash mid-run.
    const hanging = { name: "hanging", generate: () => new Promise<string>(() => undefined) };
    const first = await startGateway({ backend: hanging });
    const device = await pairDevice(first);
    await call(first.url, "POST", "/v1/jobs", { body: submission(), token: device.token });
    await new Promise((resolve) => setTimeout(resolve, 50));
    expect(
      (await call(first.url, "GET", "/v1/jobs/job-1", { token: device.token })).json,
    ).toMatchObject({
      state: "processing",
    });
    await first.stop();

    const second = await startGateway({
      backend: new ScriptedBackend([validSummary]),
      dbPath: first.dbPath,
    });
    await second.app.idle();
    const session = await call(second.url, "POST", "/v1/sessions", {
      body: { deviceId: device.deviceId, deviceSecret: device.deviceSecret },
    });
    const token2 = (session.json as { sessionToken: string }).sessionToken;

    expect((await call(second.url, "GET", "/v1/jobs/job-1", { token: token2 })).json).toMatchObject(
      {
        state: "completed",
        attempts: 2,
      },
    );
    expect(second.logs.some((line) => line.msg === "requeued jobs interrupted by a restart")).toBe(
      true,
    );
  });
});
