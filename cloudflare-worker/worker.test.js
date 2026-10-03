import assert from "node:assert/strict";
import { createHmac, webcrypto } from "node:crypto";
import test from "node:test";

import { readAndSanitizeRequest, UsageLedger, verifyPaddleSignature } from "./worker.js";

globalThis.crypto ??= webcrypto;

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
  assert.deepEqual(await blocked.json(), { allowed: false, unlimited: false, remaining: 0 });
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
  assert.deepEqual(await response.json(), { allowed: true, unlimited: true, remaining: null });
});

class MemoryStorage {
  constructor() { this.values = new Map(); }
  async get(key) { return this.values.get(key); }
  async put(key, value) { this.values.set(key, value); }
  async transaction(callback) { return callback(this); }
}
