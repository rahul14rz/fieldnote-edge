import { randomUUID } from "node:crypto";
import type { IncomingMessage } from "node:http";

import type {
  HealthResponse,
  JobStatus,
  JobSubmission,
  MeetingSummary,
} from "@fieldnote/contracts";
import healthResponseSchema from "@fieldnote/contracts/schema/health-response.schema.json" with { type: "json" };
import jobStatusSchema from "@fieldnote/contracts/schema/job-status.schema.json" with { type: "json" };
import jobSubmissionSchema from "@fieldnote/contracts/schema/job-submission.schema.json" with { type: "json" };
import meetingSummarySchema from "@fieldnote/contracts/schema/meeting-summary.schema.json" with { type: "json" };
import Fastify, { type FastifyInstance, LogController } from "fastify";

import packageJson from "../package.json" with { type: "json" };
import type { Env } from "./env.js";
import type { InferenceBackend } from "./jobs/backend.js";
import type { JobStore } from "./jobs/store.js";
import { JobWorker } from "./jobs/worker.js";

export const CORRELATION_HEADER = "x-request-id";
const SAFE_CORRELATION_ID = /^[A-Za-z0-9._-]{1,64}$/;

function correlationId(request: IncomingMessage): string {
  const incoming = request.headers[CORRELATION_HEADER];
  return typeof incoming === "string" && SAFE_CORRELATION_ID.test(incoming)
    ? incoming
    : randomUUID();
}

const errorSchema = {
  type: "object",
  required: ["message"],
  properties: { message: { type: "string" } },
} as const;

export interface AppOptions {
  env: Pick<Env, "LOG_LEVEL">;
  store: JobStore;
  /** Without a backend the gateway refuses new jobs with 503. */
  backend?: InferenceBackend;
  logStream?: { write(line: string): void };
}

export interface App {
  server: FastifyInstance;
  /** Resolves when the worker has no job left to process. */
  idle(): Promise<void>;
}

export function buildApp({ env, store, backend, logStream }: AppOptions): App {
  const server = Fastify({
    logger: logStream ? { level: env.LOG_LEVEL, stream: logStream } : { level: env.LOG_LEVEL },
    genReqId: correlationId,
    logController: new LogController({ requestIdLogLabel: "correlationId" }),
  });
  server.addSchema(meetingSummarySchema);
  const worker = backend ? new JobWorker(store, backend, server.log) : undefined;

  server.addHook("onRequest", async (request, reply) => {
    reply.header(CORRELATION_HEADER, request.id);
  });

  server.addHook("onReady", (done) => {
    const recovered = store.recoverInterrupted();
    if (recovered > 0) server.log.info({ recovered }, "requeued jobs interrupted by a restart");
    worker?.kick();
    done();
  });

  server.get(
    "/health",
    { schema: { response: { 200: healthResponseSchema } } },
    (): HealthResponse => ({
      status: "ok",
      service: "fieldnote-gateway",
      version: packageJson.version,
    }),
  );

  server.post<{ Body: JobSubmission; Reply: JobStatus | { message: string } }>(
    "/v1/jobs",
    {
      schema: {
        body: jobSubmissionSchema,
        response: {
          200: jobStatusSchema,
          202: jobStatusSchema,
          409: errorSchema,
          503: errorSchema,
        },
      },
    },
    async (request, reply) => {
      if (!worker) {
        return reply
          .code(503)
          .send({ message: "no inference backend is configured on the gateway" });
      }
      const result = store.submit(request.body);
      if (result.outcome === "conflict") {
        return reply
          .code(409)
          .send({ message: `job ${request.body.jobId} already exists with a different body` });
      }
      if (result.outcome !== "existing") worker.kick();
      return reply.code(result.outcome === "existing" ? 200 : 202).send(result.job.status);
    },
  );

  server.get<{ Params: { jobId: string }; Reply: JobStatus | { message: string } }>(
    "/v1/jobs/:jobId",
    { schema: { response: { 200: jobStatusSchema, 404: errorSchema } } },
    async (request, reply) => {
      const job = store.get(request.params.jobId);
      if (!job) return reply.code(404).send({ message: "no such job" });
      return job.status;
    },
  );

  server.get<{ Params: { jobId: string }; Reply: MeetingSummary | { message: string } }>(
    "/v1/jobs/:jobId/summary",
    { schema: { response: { 200: meetingSummarySchema, 404: errorSchema, 409: errorSchema } } },
    async (request, reply) => {
      const job = store.get(request.params.jobId);
      if (!job) return reply.code(404).send({ message: "no such job" });
      if (job.summary === null) {
        return reply.code(409).send({ message: `job is ${job.status.state}, not completed` });
      }
      return job.summary;
    },
  );

  return { server, idle: async () => worker?.idle() };
}
