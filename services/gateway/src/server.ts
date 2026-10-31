import { mkdirSync } from "node:fs";
import { hostname } from "node:os";
import { join } from "node:path";

import { buildApp } from "./app.js";
import { AuthStore } from "./auth/store.js";
import { type Env, EnvError, parseEnv } from "./env.js";
import type { InferenceBackend } from "./jobs/backend.js";
import { OpenAiCompatibleBackend } from "./jobs/openai-compatible.js";
import { JobStore } from "./jobs/store.js";
import { advertisement, bonjourPublisher, type Publisher } from "./mdns.js";
import { loadOrCreateIdentity } from "./tls/identity.js";

const LOOPBACK = new Set(["127.0.0.1", "::1", "localhost"]);

export function backendFor(env: Env): InferenceBackend | undefined {
  if (env.INFERENCE_BACKEND === "none") return undefined;
  return new OpenAiCompatibleBackend({
    baseUrl: env.INFERENCE_URL ?? "",
    model: env.INFERENCE_MODEL ?? "",
    timeoutMs: env.INFERENCE_TIMEOUT_MS,
    maxOutputTokens: env.INFERENCE_MAX_OUTPUT_TOKENS,
  });
}

/** `auto` advertises only when the gateway listens beyond loopback. */
export function shouldAdvertise(env: Pick<Env, "MDNS" | "HOST">): boolean {
  return env.MDNS === "on" || (env.MDNS === "auto" && !LOOPBACK.has(env.HOST));
}

async function main(): Promise<void> {
  const env = parseEnv(process.env);
  mkdirSync(env.DATA_DIR, { recursive: true });
  const dbPath = join(env.DATA_DIR, "gateway.sqlite");
  const store = new JobStore(dbPath);
  const auth = new AuthStore(dbPath, () => new Date());
  const tls = await loadOrCreateIdentity(join(env.DATA_DIR, "tls"));
  const backend = backendFor(env);
  const { server } = buildApp({ env, store, auth, tls, ...(backend ? { backend } : {}) });
  server.log.info(
    {
      fingerprint: tls.fingerprint,
      backend: backend?.name ?? "none",
      model: env.INFERENCE_MODEL ?? null,
    },
    "gateway configured",
  );

  let publisher: Publisher | undefined;
  for (const signal of ["SIGINT", "SIGTERM"] as const) {
    process.once(signal, () => {
      void (publisher?.stop() ?? Promise.resolve())
        .then(() => server.close())
        .then(() => {
          store.close();
          auth.close();
          process.exit(0);
        });
    });
  }

  await server.listen({ host: env.HOST, port: env.PORT });
  if (shouldAdvertise(env)) {
    const address = server.server.address();
    const port = typeof address === "object" && address ? address.port : env.PORT;
    publisher = bonjourPublisher();
    publisher.publish(advertisement(port, tls.fingerprint, hostname()));
    server.log.info({ port }, "advertising _fieldnote._tcp over mDNS");
  }
}

if (process.argv[1]?.endsWith("server.js") || process.argv[1]?.endsWith("server.ts")) {
  main().catch((error: unknown) => {
    console.error(error instanceof EnvError ? error.message : error);
    process.exit(1);
  });
}
