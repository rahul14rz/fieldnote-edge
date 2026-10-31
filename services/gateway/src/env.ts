import { z } from "zod";

const EnvSchema = z
  .object({
    HOST: z.string().min(1).default("127.0.0.1"),
    PORT: z.coerce.number().int().min(0).max(65_535).default(8787),
    LOG_LEVEL: z
      .enum(["fatal", "error", "warn", "info", "debug", "trace", "silent"])
      .default("info"),
    DATA_DIR: z.string().min(1).default("./data"),
    INFERENCE_BACKEND: z.enum(["none", "openai-compatible"]).default("none"),
    INFERENCE_URL: z.url().optional(),
    INFERENCE_MODEL: z.string().min(1).optional(),
    INFERENCE_TIMEOUT_MS: z.coerce.number().int().positive().default(600_000),
    INFERENCE_MAX_OUTPUT_TOKENS: z.coerce.number().int().positive().default(2048),
    MDNS: z.enum(["auto", "on", "off"]).default("auto"),
  })
  .superRefine((env, ctx) => {
    if (env.INFERENCE_BACKEND === "openai-compatible") {
      for (const key of ["INFERENCE_URL", "INFERENCE_MODEL"] as const) {
        if (env[key] === undefined) {
          ctx.addIssue({
            code: "custom",
            path: [key],
            message: "required when INFERENCE_BACKEND=openai-compatible",
          });
        }
      }
    }
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
