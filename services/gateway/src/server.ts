import { mkdirSync } from "node:fs";
import { join } from "node:path";

import { buildApp } from "./app.js";
import { AuthStore } from "./auth/store.js";
import { EnvError, parseEnv } from "./env.js";
import { JobStore } from "./jobs/store.js";
import { loadOrCreateIdentity } from "./tls/identity.js";

async function main(): Promise<void> {
  const env = parseEnv(process.env);
  mkdirSync(env.DATA_DIR, { recursive: true });
  const dbPath = join(env.DATA_DIR, "gateway.sqlite");
  const store = new JobStore(dbPath);
  const auth = new AuthStore(dbPath, () => new Date());
  const tls = await loadOrCreateIdentity(join(env.DATA_DIR, "tls"));
  // INFERENCE_BACKEND=none is the only value until a Mac model is chosen, so
  // the gateway answers 503 to new jobs.
  const { server } = buildApp({ env, store, auth, tls });
  server.log.info({ fingerprint: tls.fingerprint }, "TLS certificate loaded");

  for (const signal of ["SIGINT", "SIGTERM"] as const) {
    process.once(signal, () => {
      void server.close().then(() => {
        store.close();
        auth.close();
        process.exit(0);
      });
    });
  }

  await server.listen({ host: env.HOST, port: env.PORT });
}

main().catch((error: unknown) => {
  console.error(error instanceof EnvError ? error.message : error);
  process.exit(1);
});
