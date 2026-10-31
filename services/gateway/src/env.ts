import { z } from "zod";

const EnvSchema = z.object({
  HOST: z.string().min(1).default("127.0.0.1"),
  PORT: z.coerce.number().int().min(0).max(65_535).default(8787),
  LOG_LEVEL: z.enum(["fatal", "error", "warn", "info", "debug", "trace", "silent"]).default("info"),
});

export type Env = z.infer<typeof EnvSchema>;

export class EnvError extends Error {
  override readonly name = "EnvError";
}

export function parseEnv(source: Record<string, string | undefined>): Env {
  const result = EnvSchema.safeParse(source);
  if (!result.success) {
    const problems = result.error.issues.map(
      (issue) => `${issue.path.join(".")}: ${issue.message}`,
    );
    throw new EnvError(`Invalid environment:\n  ${problems.join("\n  ")}`);
  }
  return result.data;
}
