/**
 * Qwixit API and billing gateway.
 *
 * Required encrypted secrets: OPENAI_API_KEY (or the legacy
 * qwixit-cloudflare-key during migration) and PADDLE_WEBHOOK_SECRET.
 * Required binding: USAGE_LEDGER -> UsageLedger Durable Object.
 */

const OPENAI_URL = "https://api.openai.com/v1/responses";
const MODEL = "gpt-5.6-luna";
const FREE_ACTIONS_PER_MONTH = 30;
const MAX_BODY_BYTES = 64 * 1024;
const MAX_INPUT_CHARACTERS = 12_000;
const MAX_INSTRUCTIONS_CHARACTERS = 4_000;
const MAX_OUTPUT_TOKENS = 4_096;
const INSTALLATION_ID_PATTERN = /^[A-Za-z0-9_-]{43}$/;
const ACTIVE_SUBSCRIPTION_STATUSES = new Set(["active", "trialing", "past_due"]);
const RESETTABLE_SUBSCRIPTION_STATUSES = new Set(["active", "trialing", "past_due", "paused"]);
const PADDLE_SANDBOX_API_ORIGIN = "https://sandbox-api.paddle.com";
const PADDLE_SANDBOX_CLIENT_TOKEN = "test_30d92b2b51bf80a52edcb3bb6ea";
const PADDLE_SANDBOX_UNLIMITED_PRICE_ID = "pri_01m4135bkhzgwp4y51nf8wjkgp";

export default {
  async fetch(request, env) {
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
        return errorResponse(400, "A valid Qwixit installation identity is required.");
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
    if (url.pathname !== "/v1/responses") {
      return request.headers.get("accept")?.includes("text/html")
        ? notFoundPage()
        : errorResponse(404, "Not found.");
    }
    if (request.method !== "POST") return errorResponse(405, "Method not allowed.", {}, { Allow: "POST" });
    if (!request.headers.get("content-type")?.toLowerCase().startsWith("application/json")) {
      return errorResponse(415, "Content-Type must be application/json.");
    }

    const installationID = request.headers.get("x-qwixit-installation-id") ?? "";
    if (!INSTALLATION_ID_PATTERN.test(installationID)) {
      return errorResponse(401, "A valid Qwixit installation identity is required.", { code: "invalid_installation" });
    }
    if (!env.USAGE_LEDGER) {
      console.error("Missing USAGE_LEDGER Durable Object binding");
      return errorResponse(500, "Worker usage storage is not configured.");
    }

    let body;
    try {
      body = await readAndSanitizeRequest(request);
    } catch (error) {
      return errorResponse(400, error instanceof Error ? error.message : "Invalid request.");
    }

    const apiKey = env.OPENAI_API_KEY ?? env["qwixit-cloudflare-key"];
    if (!apiKey) {
      console.error("Missing OPENAI_API_KEY secret (or legacy qwixit-cloudflare-key)");
      return errorResponse(500, "Worker is not configured.");
    }

    const checkoutURL = `${url.origin}/billing/checkout?installation_id=${encodeURIComponent(installationID)}`;
    let quota;
    try {
      quota = await authorizeUsage(env, installationID);
    } catch (error) {
      console.error("Usage authorization failed", error instanceof Error ? error.message : "unknown error");
      return errorResponse(503, "Usage verification is temporarily unavailable.");
    }
    if (!quota.allowed) {
      return errorResponse(402, "You’re out of tokens!", {
        code: "free_limit_reached",
        checkout_url: checkoutURL,
        limit: FREE_ACTIONS_PER_MONTH,
        remaining: 0,
      });
    }

    let upstream;
    try {
      upstream = await fetch(OPENAI_URL, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
          "User-Agent": "Qwixit-Worker/1.0",
          "X-Client-Request-Id": crypto.randomUUID(),
        },
        body: JSON.stringify(body),
      });
    } catch (error) {
      console.error("OpenAI request failed", error instanceof Error ? error.message : "unknown error");
      return errorResponse(502, "The AI service is temporarily unavailable.");
    }

    const headers = securityHeaders({
      "Content-Type": upstream.headers.get("content-type") ?? "application/json",
      "X-Qwixit-Limit": String(FREE_ACTIONS_PER_MONTH),
      "X-Qwixit-Remaining": quota.unlimited ? "unlimited" : String(quota.remaining),
      "X-Qwixit-Plan": quota.unlimited ? "unlimited" : "free",
    });
    copyHeader(upstream.headers, headers, "retry-after");
    copyHeader(upstream.headers, headers, "x-request-id");
    return new Response(upstream.body, { status: upstream.status, statusText: upstream.statusText, headers });
  },
};

export class UsageLedger {
  constructor(state) {
    this.storage = state.storage;
  }

  async fetch(request) {
    const url = new URL(request.url);

    if (url.pathname === "/status") {
      if (request.method !== "GET") return errorResponse(405, "Method not allowed.");
      const subscription = (await this.storage.get("subscription")) ?? { status: "none" };
      const period = currentUTCMonth();
      const usage = (await this.storage.get("usage")) ?? { period, count: 0 };
      const count = usage.period === period ? usage.count : 0;
      const unlimited = ACTIVE_SUBSCRIPTION_STATUSES.has(subscription.status);
      return Response.json({
        plan: unlimited ? "unlimited" : "free",
        subscription_status: subscription.status,
        remaining: unlimited ? null : Math.max(0, FREE_ACTIONS_PER_MONTH - count),
      }, { headers: securityHeaders() });
    }

    if (url.pathname === "/subscription-state") {
      if (request.method !== "GET") return errorResponse(405, "Method not allowed.");
      const subscription = (await this.storage.get("subscription")) ?? { status: "none" };
      return Response.json({ subscription }, { headers: securityHeaders() });
    }

    if (request.method !== "POST") return errorResponse(405, "Method not allowed.");

    if (url.pathname === "/authorize") {
      const result = await this.storage.transaction(async (txn) => {
        const subscription = (await txn.get("subscription")) ?? { status: "none" };
        if (ACTIVE_SUBSCRIPTION_STATUSES.has(subscription.status)) {
          return { allowed: true, unlimited: true, remaining: null };
        }
        const period = currentUTCMonth();
        const usage = (await txn.get("usage")) ?? { period, count: 0 };
        const count = usage.period === period ? usage.count : 0;
        if (count >= FREE_ACTIONS_PER_MONTH) {
          return { allowed: false, unlimited: false, remaining: 0 };
        }
        const nextCount = count + 1;
        await txn.put("usage", { period, count: nextCount });
        return { allowed: true, unlimited: false, remaining: FREE_ACTIONS_PER_MONTH - nextCount };
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
}

async function authorizeUsage(env, installationID) {
  const id = env.USAGE_LEDGER.idFromName(installationID);
  const response = await env.USAGE_LEDGER.get(id).fetch("https://usage.qwixit/authorize", { method: "POST" });
  if (!response.ok) throw new Error("Usage ledger authorization failed.");
  return response.json();
}

async function billingStatusResponse(env, installationID) {
  const id = env.USAGE_LEDGER.idFromName(installationID);
  const response = await env.USAGE_LEDGER.get(id).fetch("https://usage.qwixit/status");
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
    return errorResponse(400, "A valid Qwixit installation identity is required.");
  }
  if (!env.USAGE_LEDGER) return errorResponse(500, "Worker usage storage is not configured.");

  const id = env.USAGE_LEDGER.idFromName(installationID);
  const ledger = env.USAGE_LEDGER.get(id);
  const stateResponse = await ledger.fetch("https://usage.qwixit/subscription-state");
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

  const response = await ledger.fetch("https://usage.qwixit/reset", { method: "POST" });
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
    url.searchParams.set("price_id", PADDLE_SANDBOX_UNLIMITED_PRICE_ID);
    url.searchParams.set("status", "active,past_due,paused");
    url.searchParams.set("per_page", "200");
    if (after) url.searchParams.set("after", after);

    const response = await fetchImplementation(url.toString(), {
      headers: { Authorization: `Bearer ${apiKey}`, "Paddle-Version": "1" },
    });
    if (!response.ok) return paddleFailure(response);

    const body = await response.json();
    for (const candidate of body?.data ?? []) {
      if (candidate?.custom_data?.qwixit_installation_id === installationID && candidate?.id) {
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

  const rawBody = await request.text();
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

  const installationID = event.data?.custom_data?.qwixit_installation_id;
  if (!INSTALLATION_ID_PATTERN.test(installationID ?? "")) {
    return Response.json({ accepted: true }, { headers: securityHeaders() });
  }
  const matchingItem = event.data?.items?.find(
    (item) => item?.price?.id === PADDLE_SANDBOX_UNLIMITED_PRICE_ID,
  );
  const status = matchingItem ? String(event.data?.status ?? "none") : "none";
  const id = env.USAGE_LEDGER.idFromName(installationID);
  const response = await env.USAGE_LEDGER.get(id).fetch("https://usage.qwixit/subscription", {
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
  if (!INSTALLATION_ID_PATTERN.test(installationID)) return errorResponse(400, "Open checkout from the Qwixit app.");
  const successUrl = `${url.origin}/billing/success?installation_id=${encodeURIComponent(installationID)}`;
  const html = `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Qwixit Unlimited</title><script src="https://cdn.paddle.com/paddle/v2/paddle.js"></script>
    <style>:root{color-scheme:light;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}body{margin:0;min-height:100vh;display:grid;place-items:center;background:#f5f3ee;color:#16131f}main{width:min(440px,calc(100% - 40px));padding:32px;border:1px solid #dedbd4;border-radius:18px;background:white;box-shadow:0 18px 60px rgba(17,21,20,.08)}.eyebrow{margin:0 0 10px;color:#6959d9;font:700 12px/1.2 "JetBrains Mono",ui-monospace,SFMono-Regular,Menlo,monospace;letter-spacing:.08em}h1{margin:0;font-size:32px;letter-spacing:-.04em}.price-row{display:flex;align-items:center;gap:14px;margin:18px 0 4px}.price{margin:0;font-size:28px;font-weight:750}.face{white-space:pre;font:800 15px/1 "JetBrains Mono",ui-monospace,SFMono-Regular,Menlo,monospace;text-shadow:-1.25px 0 #00d8f0,1.25px 0 #ff2d9b}.billing-details{margin:0 0 24px;color:#646b68}button{width:100%;min-height:48px;border:0;border-radius:12px;background:#16131f;color:white;font:inherit;font-weight:700;cursor:pointer}button:disabled{cursor:wait;opacity:.55}button:focus-visible{outline:3px solid #d9ccff;outline-offset:3px}#status{min-height:20px;margin:14px 0 0;color:#646b68;font-size:13px;text-align:center}@media(prefers-reduced-motion:reduce){.face{animation:none}}</style>
  </head>
  <body><main><p class="eyebrow">Qwixit sandbox</p><h1>Unlimited</h1><div class="price-row"><p class="price">$10 / month</p><span class="face" data-open="[ ¬_¬ ]" data-shut="[ -_- ]">[ ¬_¬ ]</span></div><p class="billing-details">Unlimited AI actions. Cancel anytime. Sandbox test payments only.</p><button id="checkout" disabled>Preparing checkout…</button><p id="status" role="status"></p></main>
    <script>
      const button=document.getElementById("checkout");const status=document.getElementById("status");
      Paddle.Environment.set("sandbox");
      Paddle.Initialize({token:${JSON.stringify(PADDLE_SANDBOX_CLIENT_TOKEN)},eventCallback(event){if(event.name==="checkout.completed")status.textContent="Payment completed. Activating Unlimited…";if(event.name==="checkout.payment.error")status.textContent="The test payment failed. Try another test card.";}});
      function openCheckout(){status.textContent="";Paddle.Checkout.open({items:[{priceId:${JSON.stringify(PADDLE_SANDBOX_UNLIMITED_PRICE_ID)},quantity:1}],customData:{qwixit_installation_id:${JSON.stringify(installationID)}},settings:{variant:"one-page",successUrl:${JSON.stringify(successUrl)}}});}
      button.disabled=false;button.textContent="Go unlimited";button.addEventListener("click",openCheckout);openCheckout();
      if(!matchMedia("(prefers-reduced-motion: reduce)").matches){const face=document.querySelector(".face");setInterval(()=>{face.textContent=face.dataset.shut;setTimeout(()=>face.textContent=face.dataset.open,170)},4200)}
    </script>
  </body>
</html>`;
  return new Response(html, { headers: securityHeaders({ "Content-Type": "text/html; charset=utf-8", "Referrer-Policy": "no-referrer", "X-Frame-Options": "DENY" }) });
}

function checkoutSuccessPage(url) {
  const installationID = url.searchParams.get("installation_id") ?? "";
  if (!INSTALLATION_ID_PATTERN.test(installationID)) return errorResponse(400, "Open checkout from the Qwixit app.");
  const statusUrl = `${url.origin}/billing/status?installation_id=${encodeURIComponent(installationID)}`;
  const html = `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
    <title>Activating Unlimited · Qwixit</title>
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
  <body><main aria-live="polite"><span class="face" id="face">[ @_@ ]</span><h1 id="title">Payment received.</h1><p id="message">Activating Unlimited… keep Qwixit open.</p><div class="track" id="track" aria-hidden="true"><span></span><span></span><span></span></div><button id="retry" hidden>Check again</button></main>
    <script>
      const face=document.getElementById("face"),title=document.getElementById("title"),message=document.getElementById("message"),track=document.getElementById("track"),retry=document.getElementById("retry");
      const statusUrl=${JSON.stringify(statusUrl)};let attempts=0,timer;
      function showReady(){clearTimeout(timer);document.title="Unlimited is ready · Qwixit";face.textContent="[ ^_- ]";title.textContent="Unlimited is ready.";message.textContent="All actions are unlocked. Go Qwix something.";track.hidden=true;retry.hidden=true}
      function showDelayed(){face.textContent="[ ?_? ]";title.textContent="Still syncing.";message.textContent="Paddle is taking a little longer. Qwixit will keep checking.";retry.hidden=false}
      async function check(){retry.hidden=true;try{const response=await fetch(statusUrl,{cache:"no-store"});if(response.ok&&(await response.json()).plan==="unlimited"){showReady();return}}catch{}attempts+=1;if(attempts===12)showDelayed();timer=setTimeout(check,attempts<8?1200:attempts<20?2200:5000)}
      retry.addEventListener("click",()=>{attempts=0;face.textContent="[ @_@ ]";title.textContent="Checking again.";message.textContent="Activating Unlimited… keep Qwixit open.";track.hidden=false;check()});check();
      if(!matchMedia("(prefers-reduced-motion: reduce)").matches){setInterval(()=>{if(face.textContent==="[ @_@ ]"){face.textContent="[ -_- ]";setTimeout(()=>{if(face.textContent==="[ -_- ]")face.textContent="[ @_@ ]"},170)}},4200)}
    </script>
  </body>
</html>`;
  return new Response(html, { headers: securityHeaders({ "Content-Type": "text/html; charset=utf-8", "Referrer-Policy": "no-referrer", "X-Frame-Options": "DENY" }) });
}

function notFoundPage() {
  const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Page not found · Qwixit</title><style>:root{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#fff;background:#100b17}body{margin:0;min-height:100vh;display:grid;place-items:center}main{text-align:center;padding:32px}.face{display:block;margin-bottom:18px;white-space:pre;font:800 34px/1 "JetBrains Mono",ui-monospace,SFMono-Regular,Menlo,monospace;text-shadow:-2.8px 0 #00d8f0,2.8px 0 #ff2d9b}p{margin:0;color:#c9c1d3;font:700 14px/1.5 "JetBrains Mono",ui-monospace,SFMono-Regular,Menlo,monospace}</style></head><body><main><span class="face">[ ?_? ]</span><p>page not found.</p></main></body></html>`;
  return new Response(html, { status: 404, headers: securityHeaders({ "Content-Type": "text/html; charset=utf-8" }) });
}

export async function readAndSanitizeRequest(request) {
  const declaredLength = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(declaredLength) && declaredLength > MAX_BODY_BYTES) throw new Error("Request body is too large.");
  const rawBody = await request.arrayBuffer();
  if (rawBody.byteLength > MAX_BODY_BYTES) throw new Error("Request body is too large.");

  let source;
  try { source = JSON.parse(new TextDecoder().decode(rawBody)); } catch { throw new Error("Request body must be valid JSON."); }
  if (!isObject(source)) throw new Error("Request body must be a JSON object.");
  if (typeof source.input !== "string" || source.input.length === 0) throw new Error("input must be a non-empty string.");
  if (source.input.length > MAX_INPUT_CHARACTERS) throw new Error(`input must be at most ${MAX_INPUT_CHARACTERS} characters.`);
  if (typeof source.instructions !== "string" || source.instructions.length === 0) throw new Error("instructions must be a non-empty string.");
  if (source.instructions.length > MAX_INSTRUCTIONS_CHARACTERS) throw new Error(`instructions must be at most ${MAX_INSTRUCTIONS_CHARACTERS} characters.`);

  const body = { model: MODEL, instructions: source.instructions, input: source.input, reasoning: { effort: "none" }, max_output_tokens: outputTokenLimit(source.max_output_tokens), store: false };
  if (source.stream === true) body.stream = true;
  if (source.service_tier === "priority") body.service_tier = "priority";
  const text = sanitizeTextOptions(source.text);
  if (text) body.text = text;
  return body;
}

function outputTokenLimit(value) {
  if (typeof value !== "number" || !Number.isFinite(value)) return 2_048;
  return Math.min(Math.max(Math.trunc(value), 64), MAX_OUTPUT_TOKENS);
}

function sanitizeTextOptions(value) {
  if (!isObject(value)) return undefined;
  const result = {};
  if (["low", "medium", "high"].includes(value.verbosity)) result.verbosity = value.verbosity;
  if (isObject(value.format) && value.format.type === "json_schema") {
    const serialized = JSON.stringify(value.format);
    if (serialized.length <= 12_000 && ["qwixit_peek", "qwixit_questions"].includes(value.format.name)) result.format = value.format;
  }
  return Object.keys(result).length > 0 ? result : undefined;
}

function currentUTCMonth() { return new Date().toISOString().slice(0, 7); }
function isObject(value) { return typeof value === "object" && value !== null && !Array.isArray(value); }
function copyHeader(from, to, name) { const value = from.get(name); if (value) to.set(name, value); }
function securityHeaders(initial = {}) { return new Headers({ "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", ...initial }); }
function errorResponse(status, message, details = {}, extraHeaders = {}) {
  return Response.json({ error: { message, ...details } }, { status, headers: securityHeaders(extraHeaders) });
}
