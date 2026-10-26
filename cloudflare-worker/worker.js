/**
 * hotkeygo API and billing gateway.
 *
 * Required encrypted secrets: OPENAI_API_KEY (or the legacy
 * qwixit-cloudflare-key during migration), CLAUDE_API_SECRET,
 * ANALYTICS_DASHBOARD_SECRET, and PADDLE_WEBHOOK_SECRET.
 * Required binding: USAGE_LEDGER -> UsageLedger Durable Object.
 */

import { ACTIONS, PEEK_LENGTHS, PEEK_MODES, actionPrompt, fixPrompt, peekPrompt, wrapSelectedText } from "./prompts.js";

const OPENAI_URL = "https://api.openai.com/v1/responses";
const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const MODEL = "gpt-5.6-luna";
const ANTHROPIC_MODEL = "claude-haiku-5-5";
const ANTHROPIC_ACTION_SCHEMA = {
  type: "object",
  properties: { text: { type: "string" } },
  required: ["text"],
  additionalProperties: false,
};
const FREE_ACTIONS_PER_MONTH = 30;
const MAX_BODY_BYTES = 64 * 1024;
const MAX_WEBHOOK_BODY_BYTES = 256 * 1024;
const INSTALLATION_ID_PATTERN = /^[A-Za-z0-9_-]{43}$/;
const OPERATION_ID_PATTERN = /^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$/;
const MAX_ATTEMPTS_PER_OPERATION = 3;
const OPERATION_LIFETIME_MS = 15 * 60 * 1000;
const OPERATION_RETENTION_MS = 60 * 60 * 1000;
const ANALYTICS_RETENTION_DAYS = 365;
const MAX_REFUNDS_PER_DAY = 20;
const MAX_CLEAN_PER_DAY = 20;
const ANALYTICS_SLOW_REQUEST_THRESHOLD_MS = 10_000;
const ANALYTICS_DURATION_BUCKETS_MS = [100, 250, 500, 1_000, 2_000, 5_000, 10_000, 20_000, 30_000, 60_000, 120_000, 300_000];
// Advanced is "more room to work", not unlimited: these keep $10 above model-provider costs.
const ADVANCED_ACTIONS_PER_DAY = 300;
const ADVANCED_ACTIONS_PER_MONTH = 3_000;
const MAX_TEXT_CHARACTERS = 6_000;
const LANGUAGE_PATTERN = /^[a-z]{2,3}(-[A-Za-z0-9]{2,8})?$/;
const RATE_LIMIT_RETRY_AFTER_SECONDS = 60;
const ACTIVE_SUBSCRIPTION_STATUSES = new Set(["active", "trialing", "past_due"]);
const RESETTABLE_SUBSCRIPTION_STATUSES = new Set(["active", "trialing", "past_due", "paused"]);
const ANALYTICS_PROVIDERS = new Set(["openai", "anthropic", "unknown"]);
const ANALYTICS_TASKS = new Set(["fix", "action", "peek", "unknown"]);
const ANALYTICS_PHASES = new Set(["model", "worker"]);
const ANALYTICS_STAGES = new Set([
  "request_validation", "request_protection", "worker_configuration", "usage_check",
  "provider_request", "provider_response", "output_check", "response_handling", "unknown",
]);
const ANALYTICS_OUTCOMES = new Set([
  "success", "output_rejected", "upstream_error", "rate_limited",
  "quota_blocked", "client_error", "service_error", "worker_error",
]);
const ANALYTICS_REASONS = new Set([
  "none", "max_tokens", "provider_refusal", "incomplete_response",
  "invalid_fix_json", "invalid_fix_verdict", "empty_output", "selected_text_marker",
  "invalid_action_json", "malformed_response", "implausible_length", "upstream_failed", "provider_not_configured", "rate_limited",
  "free_limit_reached", "daily_limit", "monthly_limit", "other",
]);
const ANTHROPIC_ACTION_OUTPUT_TOKENS = 8_192;
const ANTHROPIC_ACTION_RETRY_OUTPUT_TOKENS = 16_384;
const PADDLE_SANDBOX_API_ORIGIN = "https://sandbox-api.paddle.com";
const PADDLE_SANDBOX_CLIENT_TOKEN = "test_30d92b2b51bf80a52edcb3bb6ea";
const PADDLE_SANDBOX_ADVANCED_PRICE_ID = "pri_01m4135bkhzgwp4y51nf8wjkgp";

export default {
  async fetch(request, env, executionContext) {
    const url = new URL(request.url);

    if (url.pathname === "/billing/checkout") {
      if (request.method !== "GET") return errorResponse(405, "Method not allowed.", {}, { Allow: "GET" });
      return checkoutPage(url);
    }
    if (url.pathname === "/billing/success") {
      if (request.method !== "GET") return errorResponse(405, "Method not allowed.", {}, { Allow: "GET" });
      return checkoutSuccessPage(url);
    }
    if (url.pathname === "/billing/status") {
      if (request.method !== "GET") return errorResponse(405, "Method not allowed.", {}, { Allow: "GET" });
      const installationID = url.searchParams.get("installation_id") ?? "";
      if (!INSTALLATION_ID_PATTERN.test(installationID)) {
        return errorResponse(400, "A valid hotkeygo installation identity is required.");
      }
      if (!env.USAGE_LEDGER) return errorResponse(500, "Worker usage storage is not configured.");
      return billingStatusResponse(env, installationID);
    }
    if (url.pathname === "/billing/webhook") {
      if (request.method !== "POST") return errorResponse(405, "Method not allowed.", {}, { Allow: "POST" });
      return handlePaddleWebhook(request, env);
    }
    if (url.pathname === "/development/reset") {
      if (request.method !== "POST") return errorResponse(405, "Method not allowed.", {}, { Allow: "POST" });
      return handleDevelopmentReset(request, env);
    }
    // Keep the deployed route available while clients migrate to the renamed route.
    if (url.pathname === "/v2/hotkeygo" || url.pathname === "/v2/qwix") {
      return handleHotkeyGo(request, env, executionContext);
    }
    if (url.pathname === "/internal/client-timing") return handleClientTiming(request, env);
    if (url.pathname === "/internal/analytics") return handleAnalyticsDashboard(request, env);
    return request.headers.get("accept")?.includes("text/html")
      ? notFoundPage()
      : errorResponse(404, "Not found.");
  },
};

async function handleAnalyticsDashboard(request, env) {
  const origin = request.headers.get("origin");
  const allowedOrigin = env.ANALYTICS_DASHBOARD_ORIGIN;
  const corsHeaders = origin && origin === allowedOrigin
    ? { "Access-Control-Allow-Origin": origin, "Access-Control-Allow-Headers": "Authorization", "Access-Control-Allow-Methods": "GET, OPTIONS", "Vary": "Origin" }
    : {};

  if (request.method === "OPTIONS") {
    if (!origin || origin !== allowedOrigin) return errorResponse(403, "Dashboard origin is not allowed.");
    return new Response(null, { status: 204, headers: securityHeaders(corsHeaders) });
  }
  if (request.method !== "GET") return errorResponse(405, "Method not allowed.", {}, { ...corsHeaders, Allow: "GET, OPTIONS" });
  if (!env.ANALYTICS_DASHBOARD_SECRET) return errorResponse(404, "Not found.", {}, corsHeaders);
  if (origin && origin !== allowedOrigin) return errorResponse(403, "Dashboard origin is not allowed.");
  if (env.ANALYTICS_DASHBOARD_SECRET.length < 32) {
    return errorResponse(503, "Dashboard access key is not configured securely.", {}, corsHeaders);
  }
  const clientIP = request.headers.get("cf-connecting-ip");
  if (env.IP_RATE_LIMITER && clientIP) {
    try {
      const limit = await env.IP_RATE_LIMITER.limit({ key: `dashboard:${clientIP}` });
      if (!limit.success) return errorResponse(429, "Too many dashboard requests.", {}, corsHeaders);
    } catch {
      return errorResponse(503, "Dashboard request protection is unavailable.", {}, corsHeaders);
    }
  }
  const authorization = request.headers.get("authorization") ?? "";
  if (!constantTimeEqual(authorization, `Bearer ${env.ANALYTICS_DASHBOARD_SECRET}`)) {
    return errorResponse(401, "Dashboard access key is invalid.", {}, corsHeaders);
  }
  if (!env.USAGE_LEDGER) return errorResponse(503, "Analytics storage is not configured.", {}, corsHeaders);

  const days = Math.min(90, Math.max(1, Number(new URL(request.url).searchParams.get("days")) || 30));
  // Keep this Durable Object name so the app rename does not orphan aggregates.
  const analyticsID = env.USAGE_LEDGER.idFromName("tokiri-analytics-global-v1");
  const response = await env.USAGE_LEDGER.get(analyticsID).fetch(`https://analytics.hotkeygo/analytics/query?days=${days}`);
  return new Response(response.body, {
    status: response.status,
    headers: securityHeaders({ "Content-Type": "application/json; charset=utf-8", ...corsHeaders }),
  });
}

async function handleClientTiming(request, env) {
  if (request.method !== "POST") return errorResponse(405, "Method not allowed.", {}, { Allow: "POST" });
  const clientIP = request.headers.get("cf-connecting-ip");
  if (env.IP_RATE_LIMITER && clientIP) {
    try {
      const limit = await env.IP_RATE_LIMITER.limit({ key: `client-timing:${clientIP}` });
      if (!limit.success) return errorResponse(429, "Too many timing reports.");
    } catch {
      return errorResponse(503, "Timing report protection is unavailable.");
    }
  }
  const event = await readOptionalJSON(request);
  if (!isAnalyticsClientTiming(event)) return errorResponse(400, "Invalid client timing report.");
  if (!env.USAGE_LEDGER) return errorResponse(503, "Analytics storage is not configured.");
  const analyticsID = env.USAGE_LEDGER.idFromName("tokiri-analytics-global-v1");
  return env.USAGE_LEDGER.get(analyticsID).fetch("https://analytics.hotkeygo/analytics/client-timing", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(event),
  });
}

async function handleHotkeyGo(request, env, executionContext) {
  const metrics = { provider: "unknown", task: "unknown", outcome: "worker_error", reason: "other", stage: "request_validation", modelAttempts: 0, retries: 0, modelDurationMs: 0, modelPhaseActive: false, modelStreamStartedAt: null, startedAt: Date.now() };
  const finishSlowWatch = watchSlowRequest(env, metrics, executionContext);
  let response;
  try {
    response = await handleHotkeyGoRequest(request, env, metrics);
    metrics.outcome = await analyticsOutcome(response, metrics);
  } catch (error) {
    finishSlowWatch();
    await recordAnalytics(env, metrics, executionContext);
    throw error;
  }

  if (metrics.task === "peek" && response.status === 200 && response.body) {
    const observed = observeResponseBody(response);
    const finalize = observed.completion.then(async () => {
      if (metrics.modelStreamStartedAt !== null) {
        metrics.modelDurationMs += Date.now() - metrics.modelStreamStartedAt;
        metrics.modelPhaseActive = false;
      }
      finishSlowWatch();
      await recordAnalytics(env, metrics, null);
    });
    if (executionContext && typeof executionContext.waitUntil === "function") executionContext.waitUntil(finalize);
    else void finalize;
    return observed.response;
  }

  finishSlowWatch();
  await recordAnalytics(env, metrics, executionContext);
  return response;
}

function observeResponseBody(response) {
  const reader = response.body.getReader();
  let resolveCompletion;
  let finished = false;
  const completion = new Promise((resolve) => { resolveCompletion = resolve; });
  const finish = () => {
    if (finished) return;
    finished = true;
    resolveCompletion();
  };
  const body = new ReadableStream({
    async pull(controller) {
      try {
        const result = await reader.read();
        if (result.done) {
          controller.close();
          finish();
        } else {
          controller.enqueue(result.value);
        }
      } catch (error) {
        controller.error(error);
        finish();
      }
    },
    async cancel(reason) {
      try { await reader.cancel(reason); } finally { finish(); }
    },
  });
  return {
    response: new Response(body, { status: response.status, statusText: response.statusText, headers: response.headers }),
    completion,
  };
}

function watchSlowRequest(env, metrics, executionContext) {
  if (!executionContext || typeof executionContext.waitUntil !== "function") return () => {};
  let completed = false;
  let resolveWatch;
  const watch = new Promise((resolve) => { resolveWatch = resolve; });
  const timer = setTimeout(async () => {
    if (completed) return resolveWatch();
    try {
      if (!env.USAGE_LEDGER) return;
      const event = {
        provider: ANALYTICS_PROVIDERS.has(metrics.provider) ? metrics.provider : "unknown",
        task: ANALYTICS_TASKS.has(metrics.task) ? metrics.task : "unknown",
        phase: metrics.modelPhaseActive ? "model" : "worker",
      };
      const analyticsID = env.USAGE_LEDGER.idFromName("tokiri-analytics-global-v1");
      await env.USAGE_LEDGER.get(analyticsID).fetch("https://analytics.hotkeygo/analytics/slow", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(event),
      });
    } catch {
      console.warn("Slow request could not be recorded.");
    } finally {
      resolveWatch();
    }
  }, ANALYTICS_SLOW_REQUEST_THRESHOLD_MS);
  executionContext.waitUntil(watch);
  return () => {
    completed = true;
    clearTimeout(timer);
    resolveWatch();
  };
}

async function analyticsOutcome(response, metrics) {
  if (response.status === 200) {
    metrics.reason = "none";
    return "success";
  }
  let code = "";
  try { code = (await response.clone().json())?.error?.code ?? ""; } catch { /* response may be streaming */ }
  if (code === "output_rejected") {
    if (!ANALYTICS_REASONS.has(metrics.reason) || metrics.reason === "none") metrics.reason = "other";
    return "output_rejected";
  }
  metrics.reason = ANALYTICS_REASONS.has(code) ? code : "other";
  if (code === "upstream_failed") return "upstream_error";
  if (code === "rate_limited") return "rate_limited";
  if (code === "provider_not_configured" || response.status >= 500) return "service_error";
  if (["free_limit_reached", "daily_limit", "monthly_limit"].includes(code)) return "quota_blocked";
  return "client_error";
}

function recordAnalytics(env, metrics, executionContext) {
  const event = {
    provider: ANALYTICS_PROVIDERS.has(metrics.provider) ? metrics.provider : "unknown",
    task: ANALYTICS_TASKS.has(metrics.task) ? metrics.task : "unknown",
    outcome: ANALYTICS_OUTCOMES.has(metrics.outcome) ? metrics.outcome : "worker_error",
    reason: ANALYTICS_REASONS.has(metrics.reason) ? metrics.reason : "other",
    stage: ANALYTICS_STAGES.has(metrics.stage) ? metrics.stage : "unknown",
    modelAttempts: Math.max(0, Math.min(4, Math.trunc(metrics.modelAttempts || 0))),
    retries: Math.max(0, Math.min(4, Math.trunc(metrics.retries || 0))),
    durationMs: Math.max(0, Math.min(600_000, Date.now() - metrics.startedAt)),
    modelDurationMs: Math.max(0, Math.min(600_000, Math.trunc(metrics.modelDurationMs || 0))),
  };
  const write = (async () => {
    try {
      if (!env.USAGE_LEDGER) return;
      const analyticsID = env.USAGE_LEDGER.idFromName("tokiri-analytics-global-v1");
      await env.USAGE_LEDGER.get(analyticsID).fetch("https://analytics.hotkeygo/analytics/record", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(event),
      });
    } catch {
      // Telemetry is best-effort and never affects the user's request.
      console.warn("Analytics event could not be recorded.");
    }
  })();
  if (executionContext && typeof executionContext.waitUntil === "function") {
    executionContext.waitUntil(write);
    return;
  }
  return write;
}

function isAnalyticsEvent(event) {
  return event && typeof event === "object"
    && ANALYTICS_PROVIDERS.has(event.provider)
    && ANALYTICS_TASKS.has(event.task)
    && ANALYTICS_OUTCOMES.has(event.outcome)
    && ANALYTICS_REASONS.has(event.reason)
    && ANALYTICS_STAGES.has(event.stage)
    && Number.isInteger(event.modelAttempts) && event.modelAttempts >= 0 && event.modelAttempts <= 4
    && Number.isInteger(event.retries) && event.retries >= 0 && event.retries <= 4
    && Number.isInteger(event.durationMs) && event.durationMs >= 0 && event.durationMs <= 600_000
    && Number.isInteger(event.modelDurationMs) && event.modelDurationMs >= 0 && event.modelDurationMs <= 600_000;
}

function isAnalyticsClientTiming(event) {
  return event && typeof event === "object"
    && ANALYTICS_PROVIDERS.has(event.provider) && event.provider !== "unknown"
    && ANALYTICS_TASKS.has(event.task) && event.task !== "unknown"
    && Number.isInteger(event.durationMs) && event.durationMs >= 0 && event.durationMs <= 600_000;
}

function isAnalyticsSlowEvent(event) {
  return event && typeof event === "object"
    && ANALYTICS_PROVIDERS.has(event.provider)
    && ANALYTICS_TASKS.has(event.task)
    && ANALYTICS_PHASES.has(event.phase);
}

function durationBucketIndex(durationMs) {
  const index = ANALYTICS_DURATION_BUCKETS_MS.findIndex((upperBound) => durationMs <= upperBound);
  return index === -1 ? ANALYTICS_DURATION_BUCKETS_MS.length : index;
}

function incrementDurationBucket(histogram, durationMs) {
  const index = durationBucketIndex(durationMs);
  histogram[index] = (histogram[index] ?? 0) + 1;
}

async function readProviderJSON(response, metrics) {
  const startedAt = Date.now();
  try { return await response.json(); } catch { return null; }
  finally {
    metrics.modelDurationMs += Date.now() - startedAt;
    metrics.modelPhaseActive = false;
  }
}

async function discardProviderErrorBody(response, metrics) {
  if (!response.body) {
    metrics.modelPhaseActive = false;
    return;
  }
  const startedAt = Date.now();
  try { await response.arrayBuffer(); } catch { /* Provider status remains the useful failure signal. */ }
  finally {
    metrics.modelDurationMs += Date.now() - startedAt;
    metrics.modelPhaseActive = false;
  }
}

export class UsageLedger {
  constructor(state) {
    this.storage = state.storage;
  }

  async fetch(request) {
    const url = new URL(request.url);

    if (url.pathname === "/analytics/record") {
      if (request.method !== "POST") return errorResponse(405, "Method not allowed.");
      const event = await readOptionalJSON(request);
      if (!isAnalyticsEvent(event)) return errorResponse(400, "Invalid analytics event.");
      const date = currentUTCDate();
      const key = `analytics:${date}`;
      await this.storage.transaction(async (txn) => {
        const day = (await txn.get(key)) ?? { date, byDimension: {} };
        const dimension = [event.provider, event.task, event.outcome, event.reason, event.stage].join("|");
        const row = day.byDimension[dimension] ?? {
          provider: event.provider,
          task: event.task,
          outcome: event.outcome,
          reason: event.reason,
          stage: event.stage,
          count: 0,
          modelAttempts: 0,
          retries: 0,
          latencyCount: 0,
          modelLatencyCount: 0,
          totalDurationMs: 0,
          maxDurationMs: 0,
          totalModelDurationMs: 0,
          totalWorkerDurationMs: 0,
          maxModelDurationMs: 0,
          maxWorkerDurationMs: 0,
          durationHistogram: Array(ANALYTICS_DURATION_BUCKETS_MS.length + 1).fill(0),
          modelDurationHistogram: Array(ANALYTICS_DURATION_BUCKETS_MS.length + 1).fill(0),
          workerDurationHistogram: Array(ANALYTICS_DURATION_BUCKETS_MS.length + 1).fill(0),
        };
        // Older aggregate rows are upgraded in place when the next request arrives.
        row.latencyCount ??= 0;
        row.modelLatencyCount ??= 0;
        row.durationHistogram ??= Array(ANALYTICS_DURATION_BUCKETS_MS.length + 1).fill(0);
        row.modelDurationHistogram ??= Array(ANALYTICS_DURATION_BUCKETS_MS.length + 1).fill(0);
        row.workerDurationHistogram ??= Array(ANALYTICS_DURATION_BUCKETS_MS.length + 1).fill(0);
        row.totalModelDurationMs ??= 0;
        row.totalWorkerDurationMs ??= 0;
        row.maxModelDurationMs ??= 0;
        row.maxWorkerDurationMs ??= 0;
        row.count += 1;
        row.modelAttempts += event.modelAttempts;
        row.retries += event.retries;
        row.latencyCount += 1;
        row.totalDurationMs += event.durationMs;
        row.maxDurationMs = Math.max(row.maxDurationMs, event.durationMs);
        const modelDurationMs = Math.min(event.modelDurationMs, event.durationMs);
        const workerDurationMs = event.durationMs - modelDurationMs;
        row.totalModelDurationMs += modelDurationMs;
        row.totalWorkerDurationMs += workerDurationMs;
        row.maxWorkerDurationMs = Math.max(row.maxWorkerDurationMs, workerDurationMs);
        incrementDurationBucket(row.durationHistogram, event.durationMs);
        incrementDurationBucket(row.workerDurationHistogram, workerDurationMs);
        if (event.modelAttempts > 0) {
          row.modelLatencyCount += 1;
          row.maxModelDurationMs = Math.max(row.maxModelDurationMs, modelDurationMs);
          incrementDurationBucket(row.modelDurationHistogram, modelDurationMs);
        }
        day.byDimension[dimension] = row;
        await txn.put(key, day);
      });
      await this.scheduleAnalyticsCleanup();
      return Response.json({ recorded: true }, { headers: securityHeaders() });
    }

    if (url.pathname === "/analytics/client-timing") {
      if (request.method !== "POST") return errorResponse(405, "Method not allowed.");
      const event = await readOptionalJSON(request);
      if (!isAnalyticsClientTiming(event)) return errorResponse(400, "Invalid client timing report.");
      const date = currentUTCDate();
      const key = `analytics:${date}`;
      await this.storage.transaction(async (txn) => {
        const day = (await txn.get(key)) ?? { date, byDimension: {} };
        day.clientByDimension ??= {};
        const dimension = [event.provider, event.task].join("|");
        const row = day.clientByDimension[dimension] ?? {
          provider: event.provider,
          task: event.task,
          count: 0,
          totalDurationMs: 0,
          maxDurationMs: 0,
          durationHistogram: Array(ANALYTICS_DURATION_BUCKETS_MS.length + 1).fill(0),
        };
        row.count += 1;
        row.totalDurationMs += event.durationMs;
        row.maxDurationMs = Math.max(row.maxDurationMs, event.durationMs);
        incrementDurationBucket(row.durationHistogram, event.durationMs);
        day.clientByDimension[dimension] = row;
        await txn.put(key, day);
      });
      await this.scheduleAnalyticsCleanup();
      return Response.json({ recorded: true }, { headers: securityHeaders() });
    }

    if (url.pathname === "/analytics/slow") {
      if (request.method !== "POST") return errorResponse(405, "Method not allowed.");
      const event = await readOptionalJSON(request);
      if (!isAnalyticsSlowEvent(event)) return errorResponse(400, "Invalid slow analytics event.");
      const date = currentUTCDate();
      const key = `analytics:${date}`;
      await this.storage.transaction(async (txn) => {
        const day = (await txn.get(key)) ?? { date, byDimension: {} };
        day.slowByDimension ??= {};
        const dimension = [event.provider, event.task, event.phase].join("|");
        const row = day.slowByDimension[dimension] ?? {
          provider: event.provider,
          task: event.task,
          phase: event.phase,
          count: 0,
        };
        row.count += 1;
        day.slowByDimension[dimension] = row;
        await txn.put(key, day);
      });
      await this.scheduleAnalyticsCleanup();
      return Response.json({ recorded: true }, { headers: securityHeaders() });
    }

    if (url.pathname === "/analytics/query") {
      if (request.method !== "GET") return errorResponse(405, "Method not allowed.");
      const days = Math.min(90, Math.max(1, Number(url.searchParams.get("days")) || 30));
      const cutoff = new Date(Date.now() - (days - 1) * 86_400_000).toISOString().slice(0, 10);
      const stored = await this.storage.list({ prefix: "analytics:" });
      const events = [...stored.values()]
        .filter((day) => day.date >= cutoff)
        .flatMap((day) => Object.values(day.byDimension).map((row) => ({ date: day.date, ...row })))
        .sort((left, right) => left.date.localeCompare(right.date)
          || left.provider.localeCompare(right.provider)
          || left.task.localeCompare(right.task)
          || left.outcome.localeCompare(right.outcome)
          || (left.stage ?? "unknown").localeCompare(right.stage ?? "unknown"));
      const slowEvents = [...stored.values()]
        .filter((day) => day.date >= cutoff)
        .flatMap((day) => Object.values(day.slowByDimension ?? {}).map((row) => ({ date: day.date, ...row })))
        .sort((left, right) => left.date.localeCompare(right.date)
          || left.provider.localeCompare(right.provider)
          || left.task.localeCompare(right.task)
          || left.phase.localeCompare(right.phase));
      const clientTimings = [...stored.values()]
        .filter((day) => day.date >= cutoff)
        .flatMap((day) => Object.values(day.clientByDimension ?? {}).map((row) => ({ date: day.date, ...row })))
        .sort((left, right) => left.date.localeCompare(right.date)
          || left.provider.localeCompare(right.provider)
          || left.task.localeCompare(right.task));
      return Response.json({ days, retentionDays: ANALYTICS_RETENTION_DAYS, events, slowEvents, clientTimings }, { headers: securityHeaders() });
    }

    if (url.pathname === "/status") {
      if (request.method !== "GET") return errorResponse(405, "Method not allowed.");
      const subscription = (await this.storage.get("subscription")) ?? { status: "none" };
      const period = currentUTCMonth();
      const usage = (await this.storage.get("usage")) ?? { period, count: 0 };
      const count = usage.period === period ? usage.count : 0;
      const advanced = ACTIVE_SUBSCRIPTION_STATUSES.has(subscription.status);
      return Response.json({
        plan: advanced ? "advanced" : "free",
        subscription_status: subscription.status,
        remaining: advanced ? null : Math.max(0, FREE_ACTIONS_PER_MONTH - count),
        period,
      }, { headers: securityHeaders() });
    }

    if (url.pathname === "/subscription-state") {
      if (request.method !== "GET") return errorResponse(405, "Method not allowed.");
      const subscription = (await this.storage.get("subscription")) ?? { status: "none" };
      return Response.json({ subscription }, { headers: securityHeaders() });
    }

    if (request.method !== "POST") return errorResponse(405, "Method not allowed.");

    if (url.pathname === "/authorize") {
      const operationID = (await readOptionalJSON(request))?.operationID ?? null;
      if (!operationID) return errorResponse(400, "operationID is required.");
      const now = Date.now();
      const result = await this.storage.transaction(async (txn) => {

        // Operation records hold only state, counters, and time — never request text.
        const key = `op:${operationID}`;
        const operation = await txn.get(key);
        if (operation) {
          if (operation.attempts >= MAX_ATTEMPTS_PER_OPERATION || now - operation.createdAt > OPERATION_LIFETIME_MS) {
            return { allowed: false, code: "operation_exhausted" };
          }
          if (operation.state === "charged" || operation.state === "clean") {
            // A retry of an already charged action passes even after the limit is reached.
            await txn.put(key, { ...operation, attempts: operation.attempts + 1 });
            return { ...(await quotaSnapshot(txn)), allowed: true, code: undefined };
          }
        }

        const charge = await chargeAction(txn);
        if (!charge.allowed) return charge;
        await txn.put(key, {
          state: "charged",
          attempts: (operation?.attempts ?? 0) + 1,
          createdAt: operation?.createdAt ?? now,
          counted: true,
          period: charge.period,
          day: charge.advanced ? currentUTCDate() : null,
        });
        return charge;
      });
      await this.scheduleCleanup(now);
      return Response.json(result, { headers: securityHeaders() });
    }

    if (url.pathname === "/refund") {
      const { operationID = null, reason = "failure" } = (await readOptionalJSON(request)) ?? {};
      if (!operationID) return errorResponse(400, "operationID is required.");
      // "clean" (Fix found nothing to change) and service failures have separate daily caps.
      const counterKey = reason === "clean" ? "clean" : "refunds";
      const counterLimit = reason === "clean" ? MAX_CLEAN_PER_DAY : MAX_REFUNDS_PER_DAY;
      const result = await this.storage.transaction(async (txn) => {
        const key = `op:${operationID}`;
        const operation = await txn.get(key);
        const unchanged = async () => ({ ...(await quotaSnapshot(txn)), allowed: undefined, code: undefined, refunded: false });
        if (operation?.state !== "charged") return unchanged();

        if (operation.counted) {
          const today = currentUTCDate();
          const counter = (await txn.get(counterKey)) ?? { date: today, count: 0 };
          const counterValue = counter.date === today ? counter.count : 0;
          if (counterValue >= counterLimit) return unchanged();

          const usage = await txn.get("usage");
          if (usage?.period === operation.period && usage.count > 0) {
            await txn.put("usage", { period: usage.period, count: usage.count - 1 });
          }
          const day = await txn.get("day");
          if (operation.day && day?.date === operation.day && day.count > 0) {
            await txn.put("day", { date: day.date, count: day.count - 1 });
          }
          await txn.put(counterKey, { date: today, count: counterValue + 1 });
        }
        await txn.put(key, { ...operation, state: reason === "clean" ? "clean" : "refunded" });
        return { ...(await quotaSnapshot(txn)), allowed: undefined, code: undefined, refunded: true };
      });
      return Response.json(result, { headers: securityHeaders() });
    }

    if (url.pathname === "/subscription") {
      const event = await request.json();
      const eventKey = `event:${event.eventID}`;
      const duplicate = await this.storage.get(eventKey);
      if (duplicate) return Response.json({ duplicate: true }, { headers: securityHeaders() });
      await this.storage.transaction(async (txn) => {
        const current = await txn.get("subscription");
        if (!current?.updatedAt || event.occurredAt >= current.updatedAt) {
          await txn.put("subscription", {
            id: event.subscriptionID,
            status: event.status,
            priceID: event.priceID,
            updatedAt: event.occurredAt,
          });
        }
        await txn.put(eventKey, true);
      });
      return Response.json({ applied: true }, { headers: securityHeaders() });
    }

    if (url.pathname === "/reset") {
      await this.storage.deleteAll();
      return Response.json({ reset: true }, { headers: securityHeaders() });
    }
    return errorResponse(404, "Not found.");
  }

  async alarm() {
    const cutoff = Date.now() - OPERATION_RETENTION_MS;
    const operations = await this.storage.list({ prefix: "op:" });
    const expired = [...operations].filter(([, operation]) => operation.createdAt < cutoff).map(([key]) => key);
    if (expired.length > 0) await this.storage.delete(expired);
    const analyticsCutoff = new Date(Date.now() - ANALYTICS_RETENTION_DAYS * 86_400_000).toISOString().slice(0, 10);
    const analytics = await this.storage.list({ prefix: "analytics:" });
    const oldAnalytics = [...analytics]
      .filter(([, day]) => day.date < analyticsCutoff)
      .map(([key]) => key);
    if (oldAnalytics.length > 0) await this.storage.delete(oldAnalytics);
    if (operations.size > expired.length) await this.storage.setAlarm(Date.now() + OPERATION_RETENTION_MS);
    else if (analytics.size > oldAnalytics.length) await this.storage.setAlarm(nextAnalyticsCleanupTime());
  }

  async scheduleCleanup(now) {
    if ((await this.storage.getAlarm()) === null) await this.storage.setAlarm(now + OPERATION_RETENTION_MS);
  }

  async scheduleAnalyticsCleanup() {
    if ((await this.storage.getAlarm()) === null) await this.storage.setAlarm(nextAnalyticsCleanupTime());
  }
}

function nextAnalyticsCleanupTime() {
  const now = new Date();
  return Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1, 0, 5);
}

async function chargeAction(txn) {
  const quota = await quotaSnapshot(txn);
  if (!quota.allowed) return quota;
  const usage = (await txn.get("usage")) ?? { period: quota.period, count: 0 };
  await txn.put("usage", { period: quota.period, count: (usage.period === quota.period ? usage.count : 0) + 1 });
  if (quota.advanced) {
    const today = currentUTCDate();
    const day = (await txn.get("day")) ?? { date: today, count: 0 };
    await txn.put("day", { date: today, count: (day.date === today ? day.count : 0) + 1 });
  }
  // This action is allowed even when it used the last remaining slot.
  return { ...(await quotaSnapshot(txn)), allowed: true, code: undefined };
}

async function quotaSnapshot(txn) {
  const period = currentUTCMonth();
  const subscription = (await txn.get("subscription")) ?? { status: "none" };
  const usage = (await txn.get("usage")) ?? { period, count: 0 };
  const count = usage.period === period ? usage.count : 0;
  if (ACTIVE_SUBSCRIPTION_STATUSES.has(subscription.status)) {
    const today = currentUTCDate();
    const day = (await txn.get("day")) ?? { date: today, count: 0 };
    const dayCount = day.date === today ? day.count : 0;
    const code = dayCount >= ADVANCED_ACTIONS_PER_DAY
      ? "daily_limit"
      : count >= ADVANCED_ACTIONS_PER_MONTH ? "monthly_limit" : undefined;
    return {
      allowed: code === undefined,
      code,
      advanced: true,
      remaining: null,
      dailyRemaining: Math.max(0, ADVANCED_ACTIONS_PER_DAY - dayCount),
      period,
    };
  }
  return { allowed: count < FREE_ACTIONS_PER_MONTH, advanced: false, remaining: Math.max(0, FREE_ACTIONS_PER_MONTH - count), period };
}

async function readOptionalJSON(request) {
  try { return await request.json(); } catch { return null; }
}

async function authorizeUsage(env, installationID, operationID) {
  const id = env.USAGE_LEDGER.idFromName(installationID);
  const response = await env.USAGE_LEDGER.get(id).fetch("https://usage.hotkeygo/authorize", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ operationID }),
  });
  if (!response.ok) throw new Error("Usage ledger authorization failed.");
  return response.json();
}

async function refundUsage(env, installationID, operationID, reason = "failure") {
  const id = env.USAGE_LEDGER.idFromName(installationID);
  const response = await env.USAGE_LEDGER.get(id).fetch("https://usage.hotkeygo/refund", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ operationID, reason }),
  });
  if (!response.ok) throw new Error("Usage ledger refund failed.");
  return response.json();
}

/** Refunds when possible; a failed refund keeps the action charged rather than failing the response. */
async function tryRefund(env, installationID, operationID, quota, reason) {
  try {
    return await refundUsage(env, installationID, operationID, reason);
  } catch (error) {
    console.error("Usage refund failed", error instanceof Error ? error.message : "unknown error");
    return quota;
  }
}

async function upstreamFailure(env, installationID, operationID, quota) {
  const current = await tryRefund(env, installationID, operationID, quota, "failure");
  return errorResponse(502, "The AI service is temporarily unavailable.", { code: "upstream_failed" }, hotkeygoHeaders(current));
}

function operationExhaustedResponse() {
  return errorResponse(409, "This action can’t be retried again. Your text is unchanged.", { code: "operation_exhausted" });
}

function advancedLimitResponse(quota) {
  return quota.code === "daily_limit"
    ? errorResponse(429, "You’ve reached today’s Advanced limit. It resets at midnight UTC.", { code: "daily_limit" })
    : errorResponse(429, "You’ve reached this month’s Advanced fair-use limit. Write to us if you need more.", { code: "monthly_limit" });
}

function rateLimitedResponse() {
  return errorResponse(429, "Slow down a bit.", { code: "rate_limited" }, { "Retry-After": String(RATE_LIMIT_RETRY_AFTER_SECONDS) });
}

/** Cloudflare Rate Limiting bindings keyed by installation and by IP; the IP is never stored. */
async function isRateLimited(env, installationID, request) {
  const checks = [];
  if (env.INSTALLATION_RATE_LIMITER) checks.push(env.INSTALLATION_RATE_LIMITER.limit({ key: installationID }));
  const ip = request.headers.get("cf-connecting-ip");
  if (env.IP_RATE_LIMITER && ip) checks.push(env.IP_RATE_LIMITER.limit({ key: ip }));
  try {
    return (await Promise.all(checks)).some((result) => !result.success);
  } catch (error) {
    console.error("Rate limiter failed", error instanceof Error ? error.message : "unknown error");
    return null;
  }
}

/** For Advanced, the remaining count is the actions left today. */
function hotkeygoHeaders(quota) {
  const limit = String(quota.advanced ? ADVANCED_ACTIONS_PER_DAY : FREE_ACTIONS_PER_MONTH);
  const remaining = String(quota.advanced ? quota.dailyRemaining : quota.remaining);
  const plan = quota.advanced ? "advanced" : "free";
  const period = quota.period;
  return {
    "X-HotkeyGo-Limit": limit,
    "X-HotkeyGo-Remaining": remaining,
    "X-HotkeyGo-Plan": plan,
    "X-HotkeyGo-Period": period,
    "X-Qwixit-Limit": limit,
    "X-Qwixit-Remaining": remaining,
    "X-Qwixit-Plan": plan,
    "X-Qwixit-Period": period,
  };
}

class TaskError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

/** Accepts only known tasks and enumerated parameters; nothing a client sends can become an instruction. */
export function parseHotkeyGoTask(source) {
  if (!isObject(source)) throw new TaskError(400, "invalid_task", "Request body must be a JSON object.");
  const allowed = {
    fix: ["task", "text", "priority", "provider"],
    action: ["task", "text", "priority", "provider", "action", "language"],
    peek: ["task", "text", "provider", "mode", "length", "language", "sourceLanguage"],
  }[source.task];
  if (!allowed) throw new TaskError(400, "invalid_task", "Unknown task.");
  const unknown = Object.keys(source).find((key) => !allowed.includes(key));
  if (unknown) throw new TaskError(400, "invalid_task", `Unknown field: ${unknown}.`);
  if (typeof source.text !== "string" || source.text.trim().length === 0) {
    throw new TaskError(400, "invalid_task", "text must be a non-empty string.");
  }
  if (source.text.length > MAX_TEXT_CHARACTERS) {
    throw new TaskError(413, "text_too_long", `Select at most ${MAX_TEXT_CHARACTERS} characters.`);
  }
  if (source.priority !== undefined && typeof source.priority !== "boolean") {
    throw new TaskError(400, "invalid_task", "priority must be a boolean.");
  }
  const provider = source.provider ?? "openai";
  if (provider !== "openai" && provider !== "anthropic") {
    throw new TaskError(400, "invalid_task", "Unknown AI provider.");
  }
  const language = (value, field, required) => {
    if (value === undefined && !required) return undefined;
    if (typeof value !== "string" || !LANGUAGE_PATTERN.test(value)) throw new TaskError(400, "invalid_task", `Invalid ${field}.`);
    return value;
  };

  const task = { task: source.task, text: source.text, priority: source.priority === true, provider };
  if (source.task === "action") {
    if (!ACTIONS.has(source.action)) throw new TaskError(400, "invalid_task", "Unknown action.");
    task.action = source.action;
    task.language = language(source.language, "language", source.action === "translate");
  }
  if (source.task === "peek") {
    if (!PEEK_MODES.has(source.mode)) throw new TaskError(400, "invalid_task", "Unknown Peek mode.");
    if (source.length !== undefined && !PEEK_LENGTHS.has(source.length)) throw new TaskError(400, "invalid_task", "Unknown Peek length.");
    task.mode = source.mode;
    task.length = source.length ?? "points";
    task.language = language(source.language, "language", true);
    task.sourceLanguage = language(source.sourceLanguage, "sourceLanguage", false);
  }
  return task;
}

/** Builds the OpenAI request entirely from server templates. */
export function buildHotkeyGoRequest(task, { priority = false } = {}) {
  const prompt = task.task === "fix"
    ? fixPrompt()
    : task.task === "action"
      ? actionPrompt(task.action, task.language)
      : peekPrompt(task.mode, task.length, task.language, task.sourceLanguage);
  const body = {
    model: MODEL,
    instructions: prompt.instructions,
    input: wrapSelectedText(task.text),
    reasoning: { effort: "none" },
    max_output_tokens: hotkeygoOutputTokens(task),
    store: false,
    text: task.task === "peek" ? { format: prompt.format } : { verbosity: "low", ...(prompt.format ? { format: prompt.format } : {}) },
  };
  if (task.task === "peek") body.stream = true;
  if (priority) body.service_tier = "priority";
  return body;
}

/** Builds an Anthropic Messages request while keeping prompts and output schemas server-owned. */
export function buildAnthropicHotkeyGoRequest(task) {
  const prompt = task.task === "fix"
    ? fixPrompt()
    : task.task === "action"
      ? actionPrompt(task.action, task.language)
      : peekPrompt(task.mode, task.length, task.language, task.sourceLanguage);
  const instructions = task.task === "action"
    ? `${prompt.instructions}\n\nReturn a JSON object with one string field named "text" containing the complete result.`
    : prompt.instructions;
  const body = {
    model: ANTHROPIC_MODEL,
    system: instructions,
    messages: [{ role: "user", content: wrapSelectedText(task.text) }],
    max_tokens: anthropicHotkeyGoOutputTokens(task),
    // These are short transformations; reserve the output budget for the
    // requested result instead of model reasoning.
    ...(task.task === "fix" || task.task === "action" ? { thinking: { type: "disabled" } } : {}),
    output_config: {
      format: {
        type: "json_schema",
        schema: prompt.format?.schema ?? ANTHROPIC_ACTION_SCHEMA,
      },
    },
  };
  if (task.task === "peek") body.stream = true;
  return body;
}

function normalizeAnthropicResponse(payload, task) {
  if (!payload || !Array.isArray(payload.content) || typeof payload.stop_reason !== "string") {
    return { status: "incomplete", stopReason: "malformed_response", output: [] };
  }
  if (payload.content.some((block) => block?.type === "text" && typeof block.text !== "string")) {
    return { status: "incomplete", stopReason: "malformed_response", output: [] };
  }
  const stopReason = payload?.stop_reason ?? "unknown";
  const status = stopReason === "end_turn" || stopReason === "stop_sequence"
    ? "completed"
    : "incomplete";
  if (status !== "completed") return { status, stopReason, output: [] };
  let text = payload.content
    .filter((block) => block?.type === "text")
    .map((block) => typeof block?.text === "string" ? block.text : "")
    .join("");
  if (task.task === "action") {
    try {
      const decoded = JSON.parse(text);
      if (!decoded || typeof decoded !== "object" || typeof decoded.text !== "string") {
        return { status: "completed", stopReason, output: [], formatError: "invalid_action_json" };
      }
      text = decoded.text;
    } catch {
      return { status: "completed", stopReason, output: [], formatError: "invalid_action_json" };
    }
  }
  return {
    status,
    stopReason,
    output: [{ type: "message", content: [{ type: "output_text", text }] }],
  };
}

/** Adapts Anthropic SSE to the event names already consumed by PeekClient. */
export function anthropicStreamAsResponses(source) {
  const encoder = new TextEncoder();
  if (!source) {
    return new ReadableStream({
      start(controller) {
        controller.enqueue(encoder.encode('data: {"type":"response.failed"}\n\n'));
        controller.close();
      },
    });
  }
  const reader = source.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let pendingBlocks = [];
  let stopReason;
  let terminal = false;
  let ended = false;

  const eventChunk = (type, extra = {}) => encoder.encode(`data: ${JSON.stringify({ type, ...extra })}\n\n`);
  const processBlock = (block, controller) => {
    const data = block.split(/\r?\n/)
      .filter((line) => line.startsWith("data:"))
      .map((line) => line.slice(5).trimStart())
      .join("\n");
    if (!data || data === "[DONE]") return false;
    let event;
    try { event = JSON.parse(data); } catch { return false; }
    if (event.type === "content_block_delta" && event.delta?.type === "text_delta" && typeof event.delta.text === "string") {
      controller.enqueue(eventChunk("response.output_text.delta", { delta: event.delta.text }));
    } else if (event.type === "message_delta") {
      stopReason = event.delta?.stop_reason ?? stopReason;
    } else if (event.type === "message_stop") {
      controller.enqueue(eventChunk(stopReason === "end_turn" || stopReason === "stop_sequence" ? "response.completed" : "response.incomplete"));
      return true;
    } else if (event.type === "error") {
      controller.enqueue(eventChunk("response.failed"));
      return true;
    }
    return false;
  };

  return new ReadableStream({
    async pull(controller) {
      if (terminal) {
        controller.close();
        return;
      }
      try {
        while (true) {
          while (pendingBlocks.length > 0) {
            if (processBlock(pendingBlocks.shift(), controller)) {
              terminal = true;
              await reader.cancel();
              controller.close();
              return;
            }
            if (controller.desiredSize <= 0) return;
          }
          if (ended) {
            if (buffer.trim() && processBlock(buffer, controller)) terminal = true;
            buffer = "";
            controller.close();
            return;
          }
          const { value, done } = await reader.read();
          if (done) {
            buffer += decoder.decode();
            ended = true;
            if (buffer.includes("\n\n") || buffer.includes("\r\n\r\n")) {
              pendingBlocks = buffer.split(/\r?\n\r?\n/);
              buffer = pendingBlocks.pop() ?? "";
            }
            continue;
          }
          buffer += decoder.decode(value, { stream: true });
          const blocks = buffer.split(/\r?\n\r?\n/);
          buffer = blocks.pop() ?? "";
          pendingBlocks.push(...blocks);
        }
      } catch {
        controller.enqueue(eventChunk("response.failed"));
        controller.close();
        terminal = true;
      }
    },
    async cancel(reason) {
      await reader.cancel(reason);
    },
  });
}

function hotkeygoOutputTokens(task) {
  // Rough server-side estimate: two characters per token errs high for Cyrillic and English.
  const estimate = Math.ceil(task.text.length / 2);
  if (task.task === "peek") return 4_096;
  if (task.task === "action" && task.action === "translate") return Math.min(Math.ceil(estimate * 1.6) + 128, 6_144);
  return Math.min(Math.ceil(estimate * 1.3) + 128, 4_096);
}

function anthropicHotkeyGoOutputTokens(task) {
  if (task.task === "action") return ANTHROPIC_ACTION_OUTPUT_TOKENS;
  return hotkeygoOutputTokens(task);
}

function normalizedForComparison(text) {
  return text.normalize("NFC").replace(/\r\n/g, "\n").trim();
}

/** Second line of defense: a "fix" that returns forty lines for one sentence is not a fix. */
export function plausibleOutputLength(task, input, output) {
  if (Math.abs(output.length - input.length) <= 40) return true;
  const ratio = output.length / input.length;
  const [low, high] = task.task === "fix"
    ? [0.6, 1.5]
    // Slack/formal may legitimately compress a long message; only a near-empty result is suspicious.
    : task.action === "translate" ? [0.4, 2.5] : [0.1, 2.0];
  return ratio >= low && ratio <= high;
}

/** Decides what a completed, non-streamed model response means for the client and the quota. */
export function evaluateHotkeyGoOutput(task, payload) {
  if (ANALYTICS_REASONS.has(payload?.formatError)) return { kind: "rejected", reason: payload.formatError };
  if (!payload || typeof payload !== "object" || typeof payload.status !== "string") {
    return { kind: "rejected", reason: "malformed_response" };
  }
  if (payload?.status !== "completed") {
    const reason = payload?.stopReason === "max_tokens"
      ? "max_tokens"
      : payload?.stopReason === "refusal"
        ? "provider_refusal"
        : payload?.stopReason === "malformed_response"
          ? "malformed_response"
          : "incomplete_response";
    return { kind: "rejected", reason };
  }
  if (!Array.isArray(payload.output)) return { kind: "rejected", reason: "malformed_response" };
  const output = payload.output
    .flatMap((item) => item?.content ?? [])
    .filter((content) => content?.type === "output_text")
    .map((content) => content.text ?? "")
    .join("");
  let text = output;
  if (task.task === "fix") {
    let verdict;
    try {
      ({ verdict, text } = JSON.parse(output));
    } catch {
      return { kind: "rejected", reason: "invalid_fix_json" };
    }
    if (verdict === "clean") return { kind: "clean" };
    if (verdict !== "fixed" || typeof text !== "string") return { kind: "rejected", reason: "invalid_fix_verdict" };
    if (text.trim() && normalizedForComparison(text) === normalizedForComparison(task.text)) return { kind: "clean" };
  }
  if (!text.trim()) return { kind: "rejected", reason: "empty_output" };
  if (/<\/?\s*selected_text\s*>/i.test(text)) return { kind: "rejected", reason: "selected_text_marker" };
  if (!plausibleOutputLength(task, task.text, text)) return { kind: "rejected", reason: "implausible_length" };
  return { kind: "text", text };
}

async function handleHotkeyGoRequest(request, env, metrics) {
  metrics.stage = "request_validation";
  if (request.method !== "POST") return errorResponse(405, "Method not allowed.", {}, { Allow: "POST" });
  if (!request.headers.get("content-type")?.toLowerCase().startsWith("application/json")) {
    return errorResponse(415, "Content-Type must be application/json.");
  }
  const installationID = request.headers.get("x-hotkeygo-installation-id")
    ?? request.headers.get("x-qwixit-installation-id")
    ?? "";
  if (!INSTALLATION_ID_PATTERN.test(installationID)) {
    return errorResponse(401, "A valid hotkeygo installation identity is required.", { code: "invalid_installation" });
  }
  const operationID = request.headers.get("x-hotkeygo-operation-id")
    ?? request.headers.get("x-qwixit-operation-id")
    ?? "";
  if (!OPERATION_ID_PATTERN.test(operationID)) {
    return errorResponse(400, "A valid operation identity is required.", { code: "invalid_operation" });
  }
  if (!env.USAGE_LEDGER) {
    metrics.stage = "worker_configuration";
    console.error("Missing USAGE_LEDGER Durable Object binding");
    return errorResponse(500, "Worker usage storage is not configured.");
  }
  metrics.stage = "request_protection";
  const rateLimit = await isRateLimited(env, installationID, request);
  if (rateLimit === null) {
    return errorResponse(503, "Request protection is temporarily unavailable.", { code: "rate_limiter_unavailable" });
  }
  if (rateLimit) return rateLimitedResponse();

  let task;
  try {
    const rawBody = await readLimitedBody(request, MAX_BODY_BYTES);
    if (rawBody === null) throw new TaskError(413, "text_too_long", "Request body is too large.");
    let source;
    try { source = JSON.parse(new TextDecoder().decode(rawBody)); } catch { throw new TaskError(400, "invalid_task", "Request body must be valid JSON."); }
    task = parseHotkeyGoTask(source);
  } catch (error) {
    if (error instanceof TaskError) return errorResponse(error.status, error.message, { code: error.code });
    throw error;
  }

  const provider = task.provider ?? "openai";
  metrics.provider = provider;
  metrics.task = task.task;
  const apiKey = provider === "anthropic"
    ? env.CLAUDE_API_SECRET
    : env.OPENAI_API_KEY ?? env["hotkeygo-cloudflare-key"] ?? env["qwixit-cloudflare-key"];
  if (!apiKey) {
    metrics.stage = "worker_configuration";
    if (provider === "anthropic") {
      console.error("Missing CLAUDE_API_SECRET secret");
      return errorResponse(422, "Claude is not configured on this service yet.", { code: "provider_not_configured" });
    }
    console.error("Missing OPENAI_API_KEY secret");
    return errorResponse(500, "Worker is not configured.");
  }

  let quota;
  metrics.stage = "usage_check";
  try {
    quota = await authorizeUsage(env, installationID, operationID);
  } catch (error) {
    console.error("Usage authorization failed", error instanceof Error ? error.message : "unknown error");
    return errorResponse(503, "Usage verification is temporarily unavailable.");
  }
  if (quota.code === "operation_exhausted") return operationExhaustedResponse();
  if (quota.code === "daily_limit" || quota.code === "monthly_limit") return advancedLimitResponse(quota);
  if (!quota.allowed) {
    const checkoutURL = `${new URL(request.url).origin}/billing/checkout?installation_id=${encodeURIComponent(installationID)}`;
    return errorResponse(402, "You’re out of tokens!", {
      code: "free_limit_reached",
      checkout_url: checkoutURL,
      limit: FREE_ACTIONS_PER_MONTH,
      remaining: 0,
    });
  }

  // Priority processing costs more, so only Advanced may request it.
  const priority = task.priority && quota.advanced;
  const body = provider === "anthropic"
    ? buildAnthropicHotkeyGoRequest(task)
    : buildHotkeyGoRequest(task, { priority });
  const sendToProvider = async (requestBody) => {
    metrics.stage = "provider_request";
    metrics.modelAttempts += 1;
    metrics.modelPhaseActive = true;
    const startedAt = Date.now();
    try {
      return await fetch(provider === "anthropic" ? ANTHROPIC_URL : OPENAI_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(provider === "anthropic"
            ? { "x-api-key": apiKey, "anthropic-version": "2023-06-01" }
            : {
                Authorization: `Bearer ${apiKey}`,
                "User-Agent": "hotkeygo-Worker/1.0",
                "X-Client-Request-Id": operationID,
              }),
        },
        body: JSON.stringify(requestBody),
      });
    } finally {
      metrics.modelDurationMs += Date.now() - startedAt;
    }
  };
  let upstream;
  try {
    upstream = await sendToProvider(body);
  } catch (error) {
    metrics.modelPhaseActive = false;
    console.error(`${provider} request failed`, error instanceof Error ? error.message : "unknown error");
    return upstreamFailure(env, installationID, operationID, quota);
  }
  if (!upstream.ok) {
    metrics.stage = "provider_response";
    await discardProviderErrorBody(upstream, metrics);
    console.error(`${provider} request failed`, upstream.status);
    return upstreamFailure(env, installationID, operationID, quota);
  }

  if (task.task === "peek") {
    metrics.stage = "response_handling";
    // Peek keeps streaming; normalize Anthropic's event names to the app's existing SSE contract.
    const body = provider === "anthropic" ? anthropicStreamAsResponses(upstream.body) : upstream.body;
    if (body) metrics.modelStreamStartedAt = Date.now();
    else metrics.modelPhaseActive = false;
    const headers = securityHeaders({ "Content-Type": "text/event-stream", ...hotkeygoHeaders(quota) });
    copyHeader(upstream.headers, headers, "x-request-id");
    return new Response(body, { status: 200, headers });
  }

  metrics.stage = "output_check";
  let payload = await readProviderJSON(upstream, metrics);
  if (provider === "anthropic") payload = normalizeAnthropicResponse(payload, task);
  let outcome = evaluateHotkeyGoOutput(task, payload);
  metrics.reason = outcome.kind === "rejected" && ANALYTICS_REASONS.has(outcome.reason) ? outcome.reason : "none";

  // Retry rejected Fix output once, and retry Claude Actions when its output
  // explicitly reaches max_tokens.
  const shouldRetryRejectedOutput = outcome.kind === "rejected" && (
    (task.task === "fix" && outcome.reason !== "provider_refusal") ||
    (provider === "anthropic" && task.task === "action" && outcome.reason === "max_tokens")
  );
  if (shouldRetryRejectedOutput) {
    metrics.retries += 1;
    console.warn("Retrying rejected model output", provider, task.task, outcome.reason);
    const retryInstruction = task.task === "fix"
      ? "Return a complete, minimally edited correction that matches the required JSON schema. Preserve the full selection; do not summarize or omit anything."
      : "Return the complete requested result in the required JSON schema. Preserve all content needed for the action; do not stop mid-sentence.";
    const retryBody = {
      ...body,
      ...(provider === "anthropic"
        ? {
            max_tokens: task.task === "action" ? ANTHROPIC_ACTION_RETRY_OUTPUT_TOKENS : 8_192,
            system: [body.system, retryInstruction].join("\n\n"),
          }
        : {
            max_output_tokens: 4_096,
            instructions: [body.instructions, retryInstruction].join("\n\n"),
          }),
    };
    try {
      upstream = await sendToProvider(retryBody);
    } catch (error) {
      metrics.modelPhaseActive = false;
      console.error(`${provider} retry failed`, error instanceof Error ? error.message : "unknown error");
      return upstreamFailure(env, installationID, operationID, quota);
    }
    if (!upstream.ok) {
      await discardProviderErrorBody(upstream, metrics);
      console.error(`${provider} retry failed`, upstream.status);
      return upstreamFailure(env, installationID, operationID, quota);
    }
    metrics.stage = "output_check";
    payload = await readProviderJSON(upstream, metrics);
    if (provider === "anthropic") payload = normalizeAnthropicResponse(payload, task);
    outcome = evaluateHotkeyGoOutput(task, payload);
    metrics.reason = outcome.kind === "rejected" && ANALYTICS_REASONS.has(outcome.reason) ? outcome.reason : "none";
  }

  if (outcome.kind === "clean") {
    metrics.stage = "usage_refund";
    const current = await tryRefund(env, installationID, operationID, quota, "clean");
    metrics.stage = "response_handling";
    return Response.json({ result: "clean" }, { headers: securityHeaders(hotkeygoHeaders(current)) });
  }
  if (outcome.kind === "rejected") {
    // Log only provider/task and a fixed reason code; never include selected or generated text.
    console.warn("Model output rejected", provider, task.task, outcome.reason);
    const current = await tryRefund(env, installationID, operationID, quota, "rejected");
    return errorResponse(422, "The result didn’t pass hotkeygo’s checks. Your text is unchanged.", { code: "output_rejected" }, hotkeygoHeaders(current));
  }
  metrics.stage = "response_handling";
  const result = task.task === "fix" ? { result: "fixed", text: outcome.text } : { text: outcome.text };
  return Response.json(result, { headers: securityHeaders(hotkeygoHeaders(quota)) });
}

async function billingStatusResponse(env, installationID) {
  const id = env.USAGE_LEDGER.idFromName(installationID);
  const response = await env.USAGE_LEDGER.get(id).fetch("https://usage.hotkeygo/status");
  if (!response.ok) return errorResponse(503, "Subscription status is temporarily unavailable.");
  return new Response(response.body, {
    status: response.status,
    headers: securityHeaders({ "Content-Type": "application/json; charset=utf-8" }),
  });
}

async function handleDevelopmentReset(request, env) {
  if (!env.DEVELOPMENT_RESET_SECRET) {
    console.error("Missing DEVELOPMENT_RESET_SECRET");
    return errorResponse(404, "Not found.");
  }
  const authorization = request.headers.get("authorization") ?? "";
  const expected = `Bearer ${env.DEVELOPMENT_RESET_SECRET}`;
  if (!constantTimeEqual(authorization, expected)) {
    return errorResponse(401, "Invalid reset credentials.");
  }
  if (!request.headers.get("content-type")?.toLowerCase().startsWith("application/json")) {
    return errorResponse(415, "Content-Type must be application/json.");
  }

  let installationID;
  try {
    installationID = (await request.json())?.installation_id ?? "";
  } catch {
    return errorResponse(400, "Request body must be valid JSON.");
  }
  if (!INSTALLATION_ID_PATTERN.test(installationID)) {
    return errorResponse(400, "A valid hotkeygo installation identity is required.");
  }
  if (!env.USAGE_LEDGER) return errorResponse(500, "Worker usage storage is not configured.");

  const id = env.USAGE_LEDGER.idFromName(installationID);
  const ledger = env.USAGE_LEDGER.get(id);
  const stateResponse = await ledger.fetch("https://usage.hotkeygo/subscription-state");
  if (!stateResponse.ok) return errorResponse(503, "Could not inspect the installation subscription.");
  const { subscription } = await stateResponse.json();

  if (!env.PADDLE_API_KEY) {
    console.error("Missing PADDLE_API_KEY for complete development reset");
    return errorResponse(500, "Paddle reset is not configured.");
  }

  const paddleFetch = env.PADDLE_API?.fetch?.bind(env.PADDLE_API) ?? fetch;
  const lookup = await findPaddleSandboxSubscriptions(installationID, env.PADDLE_API_KEY, paddleFetch);
  if (!lookup.ok) {
    console.error("Paddle subscription lookup failed", lookup.status, lookup.message);
    return errorResponse(502, "Could not inspect Paddle sandbox subscriptions. Nothing was reset.");
  }

  const subscriptionIDs = new Set(lookup.subscriptionIDs);
  if (subscription?.id && RESETTABLE_SUBSCRIPTION_STATUSES.has(subscription.status)) {
    subscriptionIDs.add(subscription.id);
  }

  for (const subscriptionID of subscriptionIDs) {
    const cancellation = await cancelPaddleSandboxSubscription(
      subscriptionID,
      env.PADDLE_API_KEY,
      paddleFetch,
    );
    if (!cancellation.ok) {
      console.error("Paddle subscription cancellation failed", cancellation.status, cancellation.message);
      return errorResponse(502, "Could not cancel the Paddle sandbox subscription. Nothing was reset.");
    }
  }

  const response = await ledger.fetch("https://usage.hotkeygo/reset", { method: "POST" });
  if (!response.ok) return errorResponse(503, "Could not reset the installation.");
  return Response.json({
    reset: true,
    paddle_subscriptions_canceled: subscriptionIDs.size,
  }, { headers: securityHeaders() });
}

export async function findPaddleSandboxSubscriptions(installationID, apiKey, fetchImplementation = fetch) {
  const subscriptionIDs = [];
  let after = null;

  for (let page = 0; page < 10; page += 1) {
    const url = new URL("/subscriptions", PADDLE_SANDBOX_API_ORIGIN);
    url.searchParams.set("price_id", PADDLE_SANDBOX_ADVANCED_PRICE_ID);
    url.searchParams.set("status", "active,past_due,paused");
    url.searchParams.set("per_page", "200");
    if (after) url.searchParams.set("after", after);

    const response = await fetchImplementation(url.toString(), {
      headers: { Authorization: `Bearer ${apiKey}`, "Paddle-Version": "1" },
    });
    if (!response.ok) return paddleFailure(response);

    const body = await response.json();
    for (const candidate of body?.data ?? []) {
      const candidateInstallationID = candidate?.custom_data?.hotkeygo_installation_id
        ?? candidate?.custom_data?.qwixit_installation_id;
      if (candidateInstallationID === installationID && candidate?.id) {
        subscriptionIDs.push(candidate.id);
      }
    }
    if (!body?.meta?.pagination?.has_more) break;

    const next = body.meta.pagination.next;
    try {
      after = new URL(next).searchParams.get("after");
    } catch {
      return { ok: false, status: 502, message: "invalid Paddle pagination" };
    }
    if (!after) return { ok: false, status: 502, message: "missing Paddle pagination cursor" };
  }

  return { ok: true, subscriptionIDs };
}

export async function cancelPaddleSandboxSubscription(subscriptionID, apiKey, fetchImplementation = fetch) {
  const response = await fetchImplementation(
    `${PADDLE_SANDBOX_API_ORIGIN}/subscriptions/${encodeURIComponent(subscriptionID)}/cancel`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ effective_from: "immediately" }),
    },
  );
  if (response.ok) return { ok: true, status: response.status };

  return paddleFailure(response);
}

async function paddleFailure(response) {
  let message = "unknown Paddle error";
  try {
    const body = await response.json();
    message = body?.error?.detail ?? body?.error?.code ?? message;
  } catch {
    // Avoid returning Paddle's full response body or credentials to the caller.
  }
  return { ok: false, status: response.status, message };
}

async function handlePaddleWebhook(request, env) {
  if (!env.PADDLE_WEBHOOK_SECRET) {
    console.error("Missing PADDLE_WEBHOOK_SECRET secret");
    return errorResponse(500, "Webhook is not configured.");
  }
  if (!env.USAGE_LEDGER) return errorResponse(500, "Worker usage storage is not configured.");

  const rawBytes = await readLimitedBody(request, MAX_WEBHOOK_BODY_BYTES);
  if (rawBytes === null) return errorResponse(413, "Webhook body is too large.");
  const rawBody = new TextDecoder().decode(rawBytes);
  const signature = request.headers.get("paddle-signature") ?? "";
  if (!(await verifyPaddleSignature(rawBody, signature, env.PADDLE_WEBHOOK_SECRET))) {
    return errorResponse(401, "Invalid webhook signature.");
  }

  let event;
  try {
    event = JSON.parse(rawBody);
  } catch {
    return errorResponse(400, "Webhook body must be valid JSON.");
  }
  if (!event?.event_id || !event?.event_type?.startsWith("subscription.")) {
    return Response.json({ accepted: true }, { headers: securityHeaders() });
  }

  const installationID = event.data?.custom_data?.hotkeygo_installation_id
    ?? event.data?.custom_data?.qwixit_installation_id;
  if (!INSTALLATION_ID_PATTERN.test(installationID ?? "")) {
    return Response.json({ accepted: true }, { headers: securityHeaders() });
  }
  const matchingItem = event.data?.items?.find(
    (item) => item?.price?.id === PADDLE_SANDBOX_ADVANCED_PRICE_ID,
  );
  const status = matchingItem ? String(event.data?.status ?? "none") : "none";
  const id = env.USAGE_LEDGER.idFromName(installationID);
  const response = await env.USAGE_LEDGER.get(id).fetch("https://usage.hotkeygo/subscription", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      eventID: event.event_id,
      subscriptionID: event.data?.id ?? null,
      status,
      priceID: matchingItem?.price?.id ?? null,
      occurredAt: event.occurred_at ?? new Date().toISOString(),
    }),
  });
  if (!response.ok) return errorResponse(503, "Could not persist subscription state.");
  return Response.json({ accepted: true }, { headers: securityHeaders() });
}

export async function verifyPaddleSignature(rawBody, header, secret, nowSeconds = Date.now() / 1000) {
  const parts = header.split(";");
  const timestamp = parts.find((part) => part.startsWith("ts="))?.slice(3);
  const signatures = parts.filter((part) => part.startsWith("h1=")).map((part) => part.slice(3));
  const numericTimestamp = Number(timestamp);
  if (!timestamp || signatures.length === 0 || !Number.isFinite(numericTimestamp)) return false;
  if (Math.abs(nowSeconds - numericTimestamp) > 300) return false;

  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const digest = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${timestamp}:${rawBody}`));
  const expected = [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
  return signatures.some((candidate) => constantTimeEqual(candidate, expected));
}

function constantTimeEqual(left, right) {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  return difference === 0;
}

function checkoutPage(url) {
  const installationID = url.searchParams.get("installation_id") ?? "";
  if (!INSTALLATION_ID_PATTERN.test(installationID)) return errorResponse(400, "Open checkout from the hotkeygo app.");
  const successUrl = `${url.origin}/billing/success?installation_id=${encodeURIComponent(installationID)}`;
  const html = `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
    <title>hotkeygo Advanced</title><script src="https://cdn.paddle.com/paddle/v2/paddle.js"></script>
    <style>:root{color-scheme:light;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}body{margin:0;min-height:100vh;display:grid;place-items:center;background:#f5f3ee;color:#16131f}main{width:min(440px,calc(100% - 40px));padding:32px;border:1px solid #dedbd4;border-radius:18px;background:white;box-shadow:0 18px 60px rgba(17,21,20,.08)}.eyebrow{margin:0 0 10px;color:#6959d9;font:700 12px/1.2 "JetBrains Mono",ui-monospace,SFMono-Regular,Menlo,monospace;letter-spacing:.08em}h1{margin:0;font-size:32px;letter-spacing:-.04em}.price-row{display:flex;align-items:center;gap:14px;margin:18px 0 4px}.price{margin:0;font-size:28px;font-weight:750}.face{white-space:pre;font:800 15px/1 "JetBrains Mono",ui-monospace,SFMono-Regular,Menlo,monospace;text-shadow:-1.25px 0 #00d8f0,1.25px 0 #ff2d9b}.billing-details{margin:0 0 24px;color:#646b68}button{width:100%;min-height:48px;border:0;border-radius:12px;background:#16131f;color:white;font:inherit;font-weight:700;cursor:pointer}button:disabled{cursor:wait;opacity:.55}button:focus-visible{outline:3px solid #d9ccff;outline-offset:3px}#status{min-height:20px;margin:14px 0 0;color:#646b68;font-size:13px;text-align:center}@media(prefers-reduced-motion:reduce){.face{animation:none}}</style>
  </head>
  <body><main><p class="eyebrow">hotkeygo sandbox</p><h1>Advanced</h1><div class="price-row"><p class="price">$10 / month</p><span class="face" data-open="[ ¬_¬ ]" data-shut="[ -_- ]">[ ¬_¬ ]</span></div><p class="billing-details">More room to work. Cancel anytime. Sandbox test payments only.</p><button id="checkout" disabled>Preparing checkout…</button><p id="status" role="status"></p></main>
    <script>
      const button=document.getElementById("checkout");const status=document.getElementById("status");
      Paddle.Environment.set("sandbox");
      Paddle.Initialize({token:${JSON.stringify(PADDLE_SANDBOX_CLIENT_TOKEN)},eventCallback(event){if(event.name==="checkout.completed")status.textContent="Payment completed. Activating Advanced…";if(event.name==="checkout.payment.error")status.textContent="The test payment failed. Try another test card.";}});
      function openCheckout(){status.textContent="";Paddle.Checkout.open({items:[{priceId:${JSON.stringify(PADDLE_SANDBOX_ADVANCED_PRICE_ID)},quantity:1}],customData:{hotkeygo_installation_id:${JSON.stringify(installationID)},qwixit_installation_id:${JSON.stringify(installationID)}},settings:{variant:"one-page",successUrl:${JSON.stringify(successUrl)}}});}
      button.disabled=false;button.textContent="Get Advanced";button.addEventListener("click",openCheckout);openCheckout();
      if(!matchMedia("(prefers-reduced-motion: reduce)").matches){const face=document.querySelector(".face");setInterval(()=>{face.textContent=face.dataset.shut;setTimeout(()=>face.textContent=face.dataset.open,170)},4200)}
    </script>
  </body>
</html>`;
  return new Response(html, { headers: securityHeaders({ "Content-Type": "text/html; charset=utf-8", "Referrer-Policy": "no-referrer", "X-Frame-Options": "DENY" }) });
}

function checkoutSuccessPage(url) {
  const installationID = url.searchParams.get("installation_id") ?? "";
  if (!INSTALLATION_ID_PATTERN.test(installationID)) return errorResponse(400, "Open checkout from the hotkeygo app.");
  const statusUrl = `${url.origin}/billing/status?installation_id=${encodeURIComponent(installationID)}`;
  const html = `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
    <title>Activating Advanced · hotkeygo</title>
    <style>
      :root{color-scheme:light;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:#f5f3ee;color:#16131f}
      body{margin:0;min-height:100vh;display:grid;place-items:center;background:radial-gradient(circle at 50% 45%,#fff 0,#f8f5f0 42%,#f1eee8 100%)}
      main{width:min(430px,calc(100% - 40px));padding:34px;text-align:center;border:1px solid #dedbd4;border-radius:18px;background:#fff;box-shadow:0 18px 60px rgba(22,19,31,.08)}
      .face{display:block;margin:0 0 20px;white-space:pre;font:800 28px/1 "JetBrains Mono",ui-monospace,SFMono-Regular,Menlo,monospace;text-shadow:-2px 0 #00d8f0,2px 0 #ff2d9b}
      h1{margin:0 0 10px;font-size:28px;letter-spacing:-.025em}
      p{margin:0 auto;color:#6f6979;line-height:1.55;max-width:34ch}
      .track{display:flex;justify-content:center;gap:7px;margin:24px 0 0}.track span{width:7px;height:7px;border-radius:50%;background:#d9ccff}.track span:nth-child(2){background:#9c73ff}.track span:nth-child(3){background:#6d28ff}
      button{margin-top:22px;min-height:38px;padding:0 16px;border:1px solid #d9ccff;border-radius:10px;background:#f1ecff;color:#4a12c9;font:700 13px/1 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;cursor:pointer}button[hidden]{display:none}button:focus-visible{outline:3px solid #d9ccff;outline-offset:3px}
      @media(prefers-reduced-motion:no-preference){.track span{animation:pulse 1.2s ease-in-out infinite}.track span:nth-child(2){animation-delay:.15s}.track span:nth-child(3){animation-delay:.3s}@keyframes pulse{0%,70%,100%{opacity:.28;transform:translateY(0)}35%{opacity:1;transform:translateY(-3px)}}}
    </style>
  </head>
  <body><main aria-live="polite"><span class="face" id="face">[ @_@ ]</span><h1 id="title">Payment received.</h1><p id="message">Activating Advanced… keep hotkeygo open.</p><div class="track" id="track" aria-hidden="true"><span></span><span></span><span></span></div><button id="retry" hidden>Check again</button></main>
    <script>
      const face=document.getElementById("face"),title=document.getElementById("title"),message=document.getElementById("message"),track=document.getElementById("track"),retry=document.getElementById("retry");
      const statusUrl=${JSON.stringify(statusUrl)};let attempts=0,timer;
      function showReady(){clearTimeout(timer);document.title="Advanced is ready · hotkeygo";face.textContent="[ ^_- ]";title.textContent="Advanced is ready.";message.textContent="Advanced is active. hotkeygo is ready.";track.hidden=true;retry.hidden=true}
      function showDelayed(){face.textContent="[ ?_? ]";title.textContent="Still syncing.";message.textContent="Paddle is taking a little longer. hotkeygo will keep checking.";retry.hidden=false}
      async function check(){retry.hidden=true;try{const response=await fetch(statusUrl,{cache:"no-store"});if(response.ok&&(await response.json()).plan==="advanced"){showReady();return}}catch{}attempts+=1;if(attempts===12)showDelayed();timer=setTimeout(check,attempts<8?1200:attempts<20?2200:5000)}
      retry.addEventListener("click",()=>{attempts=0;face.textContent="[ @_@ ]";title.textContent="Checking again.";message.textContent="Activating Advanced… keep hotkeygo open.";track.hidden=false;check()});check();
      if(!matchMedia("(prefers-reduced-motion: reduce)").matches){setInterval(()=>{if(face.textContent==="[ @_@ ]"){face.textContent="[ -_- ]";setTimeout(()=>{if(face.textContent==="[ -_- ]")face.textContent="[ @_@ ]"},170)}},4200)}
    </script>
  </body>
</html>`;
  return new Response(html, { headers: securityHeaders({ "Content-Type": "text/html; charset=utf-8", "Referrer-Policy": "no-referrer", "X-Frame-Options": "DENY" }) });
}

function notFoundPage() {
  const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Page not found · hotkeygo</title><style>:root{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#fff;background:#100b17}body{margin:0;min-height:100vh;display:grid;place-items:center}main{text-align:center;padding:32px}.face{display:block;margin-bottom:18px;white-space:pre;font:800 34px/1 "JetBrains Mono",ui-monospace,SFMono-Regular,Menlo,monospace;text-shadow:-2.8px 0 #00d8f0,2.8px 0 #ff2d9b}p{margin:0;color:#c9c1d3;font:700 14px/1.5 "JetBrains Mono",ui-monospace,SFMono-Regular,Menlo,monospace}</style></head><body><main><span class="face">[ ?_? ]</span><p>page not found.</p></main></body></html>`;
  return new Response(html, { status: 404, headers: securityHeaders({ "Content-Type": "text/html; charset=utf-8" }) });
}

function currentUTCMonth() { return new Date().toISOString().slice(0, 7); }
function currentUTCDate() { return new Date().toISOString().slice(0, 10); }
function isObject(value) { return typeof value === "object" && value !== null && !Array.isArray(value); }
async function readLimitedBody(request, maximumBytes) {
  const declaredLength = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(declaredLength) && declaredLength > maximumBytes) return null;

  const reader = request.body?.getReader();
  if (!reader) return new Uint8Array();
  const chunks = [];
  let totalBytes = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      totalBytes += value.byteLength;
      if (totalBytes > maximumBytes) {
        await reader.cancel().catch(() => {});
        return null;
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }

  const body = new Uint8Array(totalBytes);
  let offset = 0;
  for (const chunk of chunks) {
    body.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return body;
}
function copyHeader(from, to, name) { const value = from.get(name); if (value) to.set(name, value); }
function securityHeaders(initial = {}) { return new Headers({ "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", ...initial }); }
function errorResponse(status, message, details = {}, extraHeaders = {}) {
  return Response.json({ error: { message, ...details } }, { status, headers: securityHeaders(extraHeaders) });
}
