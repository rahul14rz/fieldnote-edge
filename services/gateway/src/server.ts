import { mkdirSync } from "node:fs";
import { join } from "node:path";

import { buildApp } from "./app.js";
import { EnvError, parseEnv } from "./env.js";
import { JobStore } from "./jobs/store.js";

async function main(): Promise<void> {
  const env = parseEnv(process.env);
  mkdirSync(env.DATA_DIR, { recursive: true });
  const store = new JobStore(join(env.DATA_DIR, "gateway.sqlite"));
  // INFERENCE_BACKEND=none is the only value until a Mac model is chosen, so
  // the gateway answers 503 to new jobs.
  const { server } = buildApp({ env, store });

  for (const signal of ["SIGINT", "SIGTERM"] as const) {
    process.once(signal, () => {
      void server.close().then(() => {
        store.close();
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
