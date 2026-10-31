import { randomUUID } from "node:crypto";
import type { IncomingMessage } from "node:http";

import type {
  HealthResponse,
  JobStatus,
  JobSubmission,
  MeetingSummary,
  PairingRequest,
  PairingResponse,
  SessionRequest,
  SessionResponse,
} from "@fieldnote/contracts";
import healthResponseSchema from "@fieldnote/contracts/schema/health-response.schema.json" with { type: "json" };
import jobStatusSchema from "@fieldnote/contracts/schema/job-status.schema.json" with { type: "json" };
import jobSubmissionSchema from "@fieldnote/contracts/schema/job-submission.schema.json" with { type: "json" };
import meetingSummarySchema from "@fieldnote/contracts/schema/meeting-summary.schema.json" with { type: "json" };
import pairingRequestSchema from "@fieldnote/contracts/schema/pairing-request.schema.json" with { type: "json" };
import pairingResponseSchema from "@fieldnote/contracts/schema/pairing-response.schema.json" with { type: "json" };
import sessionRequestSchema from "@fieldnote/contracts/schema/session-request.schema.json" with { type: "json" };
import sessionResponseSchema from "@fieldnote/contracts/schema/session-response.schema.json" with { type: "json" };
import Fastify, { type FastifyInstance, type FastifyRequest, LogController } from "fastify";

import packageJson from "../package.json" with { type: "json" };
import type { AuthStore } from "./auth/store.js";
import type { Env } from "./env.js";
import type { InferenceBackend } from "./jobs/backend.js";
import type { JobStore } from "./jobs/store.js";
import { JobWorker } from "./jobs/worker.js";

export const CORRELATION_HEADER = "x-request-id";
const SAFE_CORRELATION_ID = /^[A-Za-z0-9._-]{1,64}$/;

/** Failed pairing attempts allowed per window before the gateway answers 429. */
export const PAIRING_FAILURE_LIMIT = 5;
export const PAIRING_FAILURE_WINDOW_MS = 60_000;

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

interface ErrorBody {
  message: string;
}

declare module "fastify" {
  interface FastifyRequest {
    deviceId: string;
  }
}

export interface AppOptions {
  env: Pick<Env, "LOG_LEVEL">;
  store: JobStore;
  auth: AuthStore;
  /** Without a backend the gateway refuses new jobs with 503. */
  backend?: InferenceBackend;
  now?: () => Date;
  logStream?: { write(line: string): void };
}

export interface App {
  server: FastifyInstance;
  /** Resolves when the worker has no job left to process. */
  idle(): Promise<void>;
}

function bearerToken(request: FastifyRequest): string | null {
  const header = request.headers.authorization;
  const match = header === undefined ? null : /^Bearer ([A-Za-z0-9_-]{43})$/.exec(header);
  return match?.[1] ?? null;
}

export function buildApp({
  env,
  store,
  auth,
  backend,
  now = () => new Date(),
  logStream,
}: AppOptions): App {
  const server = Fastify({
    logger: logStream ? { level: env.LOG_LEVEL, stream: logStream } : { level: env.LOG_LEVEL },
    genReqId: correlationId,
    logController: new LogController({ requestIdLogLabel: "correlationId" }),
  });
  server.addSchema(meetingSummarySchema);
  server.decorateRequest("deviceId", "");
  const worker = backend ? new JobWorker(store, backend, server.log) : undefined;
  let pairingFailures: number[] = [];

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

  server.post<{ Body: PairingRequest; Reply: PairingResponse | ErrorBody }>(
    "/v1/pairing",
    {
      schema: {
        body: pairingRequestSchema,
        response: { 201: pairingResponseSchema, 401: errorSchema, 429: errorSchema },
      },
    },
    async (request, reply) => {
      const t = now().getTime();
      pairingFailures = pairingFailures.filter((at) => t - at < PAIRING_FAILURE_WINDOW_MS);
      if (pairingFailures.length >= PAIRING_FAILURE_LIMIT) {
        return reply.code(429).send({ message: "too many failed pairing attempts; wait a minute" });
      }
      const credential = auth.redeemPairingCode(request.body.code, request.body.deviceName);
      if (!credential) {
        pairingFailures.push(t);
        request.log.warn("pairing code rejected");
        return reply
          .code(401)
          .send({ message: "the pairing code is wrong, expired or already used" });
      }
      request.log.info({ deviceId: credential.deviceId }, "device paired");
      return reply.code(201).send(credential);
    },
  );

  server.post<{ Body: SessionRequest; Reply: SessionResponse | ErrorBody }>(
    "/v1/sessions",
    {
      schema: {
        body: sessionRequestSchema,
        response: { 201: sessionResponseSchema, 401: errorSchema },
      },
    },
    async (request, reply) => {
      const session = auth.createSession(request.body.deviceId, request.body.deviceSecret);
      if (!session) {
        return reply.code(401).send({ message: "unknown or revoked device, or wrong secret" });
      }
      return reply.code(201).send(session);
    },
  );

  server.register((jobs, _options, done) => {
    jobs.addHook("preHandler", async (request, reply) => {
      const token = bearerToken(request);
      const deviceId = token === null ? null : auth.authenticate(token);
      if (deviceId === null) {
        return reply
          .code(401)
          .header("www-authenticate", "Bearer")
          .send({ message: "a valid session token is required" });
      }
      request.deviceId = deviceId;
    });

    jobs.post<{ Body: JobSubmission; Reply: JobStatus | ErrorBody }>(
      "/v1/jobs",
      {
        schema: {
          body: jobSubmissionSchema,
          response: {
            200: jobStatusSchema,
            202: jobStatusSchema,
            401: errorSchema,
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
        const result = store.submit(request.deviceId, request.body);
        if (result.outcome === "conflict") {
          return reply
            .code(409)
            .send({ message: `job ${request.body.jobId} already exists with a different body` });
        }
        if (result.outcome !== "existing") worker.kick();
        return reply.code(result.outcome === "existing" ? 200 : 202).send(result.job.status);
      },
    );

    jobs.get<{ Params: { jobId: string }; Reply: JobStatus | ErrorBody }>(
      "/v1/jobs/:jobId",
      { schema: { response: { 200: jobStatusSchema, 401: errorSchema, 404: errorSchema } } },
      async (request, reply) => {
        const job = store.get(request.deviceId, request.params.jobId);
        if (!job) return reply.code(404).send({ message: "no such job" });
        return job.status;
      },
    );

    jobs.get<{ Params: { jobId: string }; Reply: MeetingSummary | ErrorBody }>(
      "/v1/jobs/:jobId/summary",
      {
        schema: {
          response: {
            200: meetingSummarySchema,
            401: errorSchema,
            404: errorSchema,
            409: errorSchema,
          },
        },
      },
      async (request, reply) => {
        const job = store.get(request.deviceId, request.params.jobId);
        if (!job) return reply.code(404).send({ message: "no such job" });
        if (job.summary === null) {
          return reply.code(409).send({ message: `job is ${job.status.state}, not completed` });
        }
        return job.summary;
      },
    );

    done();
  });

  return { server, idle: async () => worker?.idle() };
}
