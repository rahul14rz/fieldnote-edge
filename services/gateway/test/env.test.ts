import { spawnSync } from "node:child_process";
import { join } from "node:path";

import { describe, expect, it } from "vitest";

import { EnvError, parseEnv } from "../src/env.js";

describe("parseEnv", () => {
  it("defaults to loopback so the gateway is not on the LAN before pairing exists", () => {
    expect(parseEnv({})).toEqual({
      HOST: "127.0.0.1",
      PORT: 8787,
      LOG_LEVEL: "info",
      DATA_DIR: "./data",
      INFERENCE_BACKEND: "none",
      INFERENCE_TIMEOUT_MS: 600000,
      INFERENCE_MAX_OUTPUT_TOKENS: 2048,
      MDNS: "auto",
    });
  });

  it("reads explicit values", () => {
    expect(
      parseEnv({ HOST: "0.0.0.0", PORT: "9000", LOG_LEVEL: "debug", DATA_DIR: "/var/fieldnote" }),
    ).toEqual({
      HOST: "0.0.0.0",
      PORT: 9000,
      LOG_LEVEL: "debug",
      DATA_DIR: "/var/fieldnote",
      INFERENCE_BACKEND: "none",
      INFERENCE_TIMEOUT_MS: 600000,
      INFERENCE_MAX_OUTPUT_TOKENS: 2048,
      MDNS: "auto",
    });
  });

  it.each([
    ["PORT", "not-a-number"],
    ["PORT", "70000"],
    ["LOG_LEVEL", "loud"],
    ["INFERENCE_BACKEND", "magic"],
  ])("rejects %s=%s and names the variable", (name, value) => {
    expect(() => parseEnv({ [name]: value })).toThrow(EnvError);
    expect(() => parseEnv({ [name]: value })).toThrow(name);
  });
});

describe("server startup", () => {
  it("exits with code 1 and names the bad variable instead of listening", () => {
    const gatewayDir = join(import.meta.dirname, "..");
    const result = spawnSync(
      join(gatewayDir, "node_modules", ".bin", "tsx"),
      [join(gatewayDir, "src", "server.ts")],
      { env: { ...process.env, PORT: "not-a-number" }, encoding: "utf8", timeout: 20_000 },
    );

    expect(result.status).toBe(1);
    expect(result.stderr).toContain("PORT");
  });
});
