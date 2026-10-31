import { buildApp } from "./app.js";
import { EnvError, parseEnv } from "./env.js";

async function main(): Promise<void> {
  const env = parseEnv(process.env);
  const app = buildApp({ env });

  for (const signal of ["SIGINT", "SIGTERM"] as const) {
    process.once(signal, () => {
      void app.close().then(() => process.exit(0));
    });
  }

  await app.listen({ host: env.HOST, port: env.PORT });
}

main().catch((error: unknown) => {
  console.error(error instanceof EnvError ? error.message : error);
  process.exit(1);
});
