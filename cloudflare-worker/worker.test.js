import assert from "node:assert/strict";
import { createHmac, webcrypto } from "node:crypto";
import test from "node:test";

import worker, {
  cancelPaddleSandboxSubscription,
  findPaddleSandboxSubscriptions,
  readAndSanitizeRequest,
  UsageLedger,
  verifyPaddleSignature,
} from "./worker.js";

globalThis.crypto ??= webcrypto;
const currentPeriod = new Date().toISOString().slice(0, 7);

test("sanitizes model and storage fields", async () => {
  const request = new Request("https://example.test/v1/responses", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ model: "attacker-controlled", instructions: "Translate", input: "Hello", max_output_tokens: 999_999, store: true }),
  });
  const result = await readAndSanitizeRequest(request);
  assert.equal(result.model, "gpt-5.6-luna");
  assert.equal(result.store, false);
  assert.equal(result.max_output_tokens, 4_096);
});

test("verifies current Paddle signatures", async () => {
  const body = '{"event_id":"evt_123"}';
  const timestamp = 1_700_000_000;
  const secret = "pdl_ntfset_test";
  const signature = createHmac("sha256", secret).update(`${timestamp}:${body}`).digest("hex");
  assert.equal(await verifyPaddleSignature(body, `ts=${timestamp};h1=${signature}`, secret, timestamp + 10), true);
});

test("rejects stale Paddle signatures", async () => {
  const body = "{}";
  const timestamp = 1_700_000_000;
  const secret = "pdl_ntfset_test";
  const signature = createHmac("sha256", secret).update(`${timestamp}:${body}`).digest("hex");
  assert.equal(await verifyPaddleSignature(body, `ts=${timestamp};h1=${signature}`, secret, timestamp + 301), false);
});

test("atomically stops the free plan after 30 actions", async () => {
  const ledger = new UsageLedger({ storage: new MemoryStorage() });
  for (let index = 0; index < 30; index += 1) {
    const response = await ledger.fetch(new Request("https://usage.qwixit/authorize", { method: "POST" }));
    assert.equal((await response.json()).allowed, true);
  }
  const blocked = await ledger.fetch(new Request("https://usage.qwixit/authorize", { method: "POST" }));
  assert.deepEqual(await blocked.json(), { allowed: false, unlimited: false, remaining: 0, period: currentPeriod });
});

test("active subscription unlocks unlimited actions", async () => {
  const ledger = new UsageLedger({ storage: new MemoryStorage() });
  await ledger.fetch(new Request("https://usage.qwixit/subscription", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      eventID: "evt_1",
      subscriptionID: "sub_1",
      status: "active",
      priceID: "pri_1",
      occurredAt: "2026-10-03T12:00:00Z",
    }),
  }));
  const response = await ledger.fetch(new Request("https://usage.qwixit/authorize", { method: "POST" }));
  assert.deepEqual(await response.json(), { allowed: true, unlimited: true, remaining: null, period: currentPeriod });
});

test("reports billing status without consuming a free action", async () => {
  const ledger = new UsageLedger({ storage: new MemoryStorage() });
  const before = await ledger.fetch(new Request("https://usage.qwixit/status"));
  assert.deepEqual(await before.json(), { plan: "free", subscription_status: "none", remaining: 30, period: currentPeriod });

  await ledger.fetch(new Request("https://usage.qwixit/authorize", { method: "POST" }));
  const after = await ledger.fetch(new Request("https://usage.qwixit/status"));
  assert.deepEqual(await after.json(), { plan: "free", subscription_status: "none", remaining: 29, period: currentPeriod });
});

test("exposes the read-only billing status for the mac app", async () => {
  const ledger = new UsageLedger({ storage: new MemoryStorage() });
  const namespace = {
    idFromName(value) { return value; },
    get() { return { fetch: (url, init) => ledger.fetch(new Request(url, init)) }; },
  };
  const installationID = "a".repeat(43);
  const response = await worker.fetch(
    new Request(`https://example.test/billing/status?installation_id=${installationID}`),
    { USAGE_LEDGER: namespace },
  );
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { plan: "free", subscription_status: "none", remaining: 30, period: currentPeriod });
});

test("development reset requires its secret and clears the installation ledger", async () => {
  const ledger = new UsageLedger({ storage: new MemoryStorage() });
  const namespace = {
    idFromName(value) { return value; },
    get() { return { fetch: (url, init) => ledger.fetch(new Request(url, init)) }; },
  };
  const installationID = "a".repeat(43);
  await ledger.fetch(new Request("https://usage.qwixit/authorize", { method: "POST" }));
  await ledger.fetch(new Request("https://usage.qwixit/subscription", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      eventID: "evt_reset",
      subscriptionID: "sub_reset",
      status: "active",
      priceID: "pri_reset",
      occurredAt: "2026-10-05T12:00:00Z",
    }),
  }));

  const unauthorized = await worker.fetch(
    new Request("https://example.test/development/reset", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ installation_id: installationID }),
    }),
    { USAGE_LEDGER: namespace, DEVELOPMENT_RESET_SECRET: "reset-secret" },
  );
  assert.equal(unauthorized.status, 401);

  const paddleRequests = [];
  const response = await worker.fetch(
    new Request("https://example.test/development/reset", {
      method: "POST",
      headers: {
        Authorization: "Bearer reset-secret",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ installation_id: installationID }),
    }),
    {
      USAGE_LEDGER: namespace,
      DEVELOPMENT_RESET_SECRET: "reset-secret",
      PADDLE_API_KEY: "pdl_sdbx_apikey_test",
      PADDLE_API: {
        async fetch(url, init) {
          paddleRequests.push({ url, init });
          if (url.includes("/subscriptions?")) {
            return Response.json({
              data: [{
                id: "sub_reset",
                status: "active",
                custom_data: { qwixit_installation_id: installationID },
              }],
              meta: { pagination: { has_more: false } },
            });
          }
          return Response.json({ data: { id: "sub_reset", status: "canceled" } });
        },
      },
    },
  );
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { reset: true, paddle_subscriptions_canceled: 1 });
  assert.equal(paddleRequests.length, 2);
  assert.match(paddleRequests[0].url, /^https:\/\/sandbox-api\.paddle\.com\/subscriptions\?/);
  assert.equal(paddleRequests[0].init.headers.Authorization, "Bearer pdl_sdbx_apikey_test");
  assert.equal(paddleRequests[1].url, "https://sandbox-api.paddle.com/subscriptions/sub_reset/cancel");
  assert.deepEqual(JSON.parse(paddleRequests[1].init.body), { effective_from: "immediately" });

  const status = await ledger.fetch(new Request("https://usage.qwixit/status"));
  assert.deepEqual(await status.json(), { plan: "free", subscription_status: "none", remaining: 30, period: currentPeriod });
});

test("development reset keeps the ledger intact when Paddle cancellation fails", async () => {
  const ledger = new UsageLedger({ storage: new MemoryStorage() });
  const namespace = {
    idFromName(value) { return value; },
    get() { return { fetch: (url, init) => ledger.fetch(new Request(url, init)) }; },
  };
  const installationID = "a".repeat(43);
  await ledger.fetch(new Request("https://usage.qwixit/subscription", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      eventID: "evt_keep",
      subscriptionID: "sub_keep",
      status: "active",
      priceID: "pri_keep",
      occurredAt: "2026-10-05T12:00:00Z",
    }),
  }));

  const response = await worker.fetch(
    new Request("https://example.test/development/reset", {
      method: "POST",
      headers: {
        Authorization: "Bearer reset-secret",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ installation_id: installationID }),
    }),
    {
      USAGE_LEDGER: namespace,
      DEVELOPMENT_RESET_SECRET: "reset-secret",
      PADDLE_API_KEY: "pdl_sdbx_apikey_test",
      PADDLE_API: {
        fetch(url) {
          if (url.includes("/subscriptions?")) {
            return Response.json({ data: [], meta: { pagination: { has_more: false } } });
          }
          return Response.json({ error: { code: "subscription_locked" } }, { status: 409 });
        },
      },
    },
  );

  assert.equal(response.status, 502);
  const status = await ledger.fetch(new Request("https://usage.qwixit/status"));
  assert.deepEqual(await status.json(), { plan: "unlimited", subscription_status: "active", remaining: null, period: currentPeriod });
});

test("Paddle cancellation helper uses the sandbox API and immediate cancellation", async () => {
  let captured;
  const result = await cancelPaddleSandboxSubscription("sub_123", "secret", async (url, init) => {
    captured = { url, init };
    return Response.json({ data: { status: "canceled" } });
  });

  assert.deepEqual(result, { ok: true, status: 200 });
  assert.equal(captured.url, "https://sandbox-api.paddle.com/subscriptions/sub_123/cancel");
  assert.deepEqual(JSON.parse(captured.init.body), { effective_from: "immediately" });
});

test("Paddle lookup finds every active subscription attached to an installation", async () => {
  const installationID = "a".repeat(43);
  const result = await findPaddleSandboxSubscriptions(installationID, "secret", async (url) => {
    assert.match(url, /price_id=pri_01m4135bkhzgwp4y51nf8wjkgp/);
    return Response.json({
      data: [
        { id: "sub_match", custom_data: { qwixit_installation_id: installationID } },
        { id: "sub_other", custom_data: { qwixit_installation_id: "b".repeat(43) } },
      ],
      meta: { pagination: { has_more: false } },
    });
  });

  assert.deepEqual(result, { ok: true, subscriptionIDs: ["sub_match"] });
});

class MemoryStorage {
  constructor() { this.values = new Map(); }
  async get(key) { return this.values.get(key); }
  async put(key, value) { this.values.set(key, value); }
  async deleteAll() { this.values.clear(); }
  async transaction(callback) { return callback(this); }
}
