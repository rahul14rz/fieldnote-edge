import { randomUUID } from "node:crypto";
import type { IncomingMessage } from "node:http";

import type { HealthResponse } from "@fieldnote/contracts";
import healthResponseSchema from "@fieldnote/contracts/schema/health-response.schema.json" with { type: "json" };
import Fastify, { type FastifyInstance, LogController } from "fastify";

import packageJson from "../package.json" with { type: "json" };
import type { Env } from "./env.js";

export const CORRELATION_HEADER = "x-request-id";
const SAFE_CORRELATION_ID = /^[A-Za-z0-9._-]{1,64}$/;

function correlationId(request: IncomingMessage): string {
  const incoming = request.headers[CORRELATION_HEADER];
  return typeof incoming === "string" && SAFE_CORRELATION_ID.test(incoming)
    ? incoming
    : randomUUID();
}

export interface AppOptions {
  env: Pick<Env, "LOG_LEVEL">;
  logStream?: { write(line: string): void };
}

export function buildApp({ env, logStream }: AppOptions): FastifyInstance {
  const app = Fastify({
    logger: logStream ? { level: env.LOG_LEVEL, stream: logStream } : { level: env.LOG_LEVEL },
    genReqId: correlationId,
    logController: new LogController({ requestIdLogLabel: "correlationId" }),
  });

  app.addHook("onRequest", async (request, reply) => {
    reply.header(CORRELATION_HEADER, request.id);
  });

  app.get(
    "/health",
    { schema: { response: { 200: healthResponseSchema } } },
    (): HealthResponse => ({
      status: "ok",
      service: "fieldnote-gateway",
      version: packageJson.version,
    }),
  );

  return app;
}
