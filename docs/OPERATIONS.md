# hotkeygo operations and release guide

**Status:** current development and release procedure
**Last reviewed:** 2026-10-07

## Local prerequisites

- macOS 14 or newer
- Xcode 16 or newer
- Node.js and npm for the Cloudflare Worker
- Accessibility permission for local end-to-end text replacement
- Wrangler authentication for Worker secrets and deployment
- Paddle sandbox credentials for subscription testing

The app is an `LSUIElement` menu-bar utility. App Sandbox is disabled because system-wide Accessibility replacement and Carbon hotkeys need access outside the app. Debug launches enforce one running instance per bundle identifier.

## Build and test the macOS app

Open `HotkeyGo.xcodeproj`, select the `HotkeyGo` scheme and **My Mac**, then run with `⌘R`.

For an unsigned command-line build:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project HotkeyGo.xcodeproj \
  -scheme HotkeyGo \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/HotkeyGoDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  build
```

Run the unit tests with:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project HotkeyGo.xcodeproj \
  -scheme HotkeyGo \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/HotkeyGoDerivedData \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO \
  test
```

Do not launch an additional app process casually during automated verification: single-instance coordination can terminate the instance the owner is actively testing.

### Replacement reliability check

Fix and Actions use one replacement path in every app: capture the selected text and source focus, restore the source app and focused element, put the fresh text on the clipboard, then post ⌘V. AX is used to read the selection and restore focus; it never writes the replacement or decides whether a paste succeeded. Actions' insert mode sends Right Arrow first to collapse the selection at its end, then uses the same paste path.

ReplacementAttemptReport contains only three transient steps: clipboard write, optional caret move, and ⌘V event. isSubmitted means the clipboard write completed and the required keyboard events were posted. Fix shows “Success”; this marks a completed request and posted event, not proof that another app consumed the paste. If hotkeygo cannot prepare the clipboard or post the required event, it offers the fresh text and a manual copy button. Fix leaves the correction on the system clipboard as a manual paste backup after a successful clipboard write; Actions restores the previous clipboard. Neither selected nor generated text is logged or stored in hotkeygo data.

Unit tests cover the clipboard, paste-event, and caret-move requirements for a submitted status, plus recovery when a paste event cannot be posted. Clipboard archive tests verify that Fix keeps the correction, Actions restores rich clipboard contents, and newer clipboard content is preserved. These tests do not measure delivery to real editors. Before claiming a replacement success rate, use controlled, unsent drafts in a native text control and browser editors such as Slack and GitHub, plus representative spreadsheet and messaging apps. Exercise single-line, multiline, and repeated selections; Fix, Actions replace, and Actions insert. Confirm that manual ⌘V pastes the Fix result and that Actions restores the previous clipboard. Record only pass/fail and editor category. A 99.5% delivery claim requires a sufficiently large real-editor trial; unit tests alone cannot support it.

## Worker checks

The Worker lives in `cloudflare-worker/`.

```sh
cd cloudflare-worker
npm install
npm test
npm run check
```

It proxies model requests, enforces monthly usage atomically with a Durable Object, exposes billing state, receives signed Paddle webhooks, and hosts the checkout and activation pages.

The signed Paddle webhook updates the installation ledger independently of the macOS app. The app reads that ledger through `/billing/status` on launch, after returning to the foreground, and whenever the menu opens. After checkout is opened from Settings, the menu, Fix, or Peek limit notices, the app polls every two seconds at first, then every ten seconds for a longer checkout (up to about ten minutes). The success page also polls the same status endpoint. Returning to the app or opening the menu/Settings triggers an immediate status check and restarts the same checkout poll. Verify activation in the menu without opening Settings during the sandbox journey. Paddle's sandbox can deliver or retry webhook events later than the checkout completion callback, so the success page and app can briefly show a syncing state.

Required production-like bindings and secrets:

- `USAGE_LEDGER` Durable Object binding
- `INSTALLATION_RATE_LIMITER` (20 requests/minute per installation) and `IP_RATE_LIMITER` (60 requests/minute per IP) Rate Limiting bindings from `wrangler.toml`; without them the Worker skips the per-minute guard. A configured limiter error returns `503` before usage is charged or a model is called.
- `OPENAI_API_KEY`
- `CLAUDE_API_SECRET` (needed only when Claude Haiku 5.5 is selected)
- `ANALYTICS_DASHBOARD_SECRET` (admin-only API key for the internal dashboard)
- `PADDLE_WEBHOOK_SECRET`

Development reset additionally needs:

- `DEVELOPMENT_RESET_SECRET`
- `PADDLE_API_KEY` with sandbox subscription read/write access

## Deploy the Worker

```sh
cd cloudflare-worker
npx wrangler secret put OPENAI_API_KEY
npx wrangler secret put CLAUDE_API_SECRET
npx wrangler secret put ANALYTICS_DASHBOARD_SECRET
npx wrangler secret put PADDLE_WEBHOOK_SECRET
npm run deploy
```

The Worker name and hostname remain `qwixit-api` because that is the deployed endpoint used for billing and current clients. The app continues to call `/v2/qwix` until the updated Worker is deployed; the source Worker accepts both `/v2/qwix` and `/v2/hotkeygo`. Keep both routes, headers, and Paddle metadata fields as compatibility aliases through the client migration.

The Worker retry for rejected Fix output and Claude Actions truncated at `max_tokens`, plus the analytics collector, take effect only after this deployment. Claude Actions get an 8,192-token output ceiling on the first request and a 16,384-token ceiling on the single truncation retry. The dashboard is a separate static Cloudflare Pages project; its default origin is `https://tokiri-analytics.pages.dev` in `wrangler.toml`. If Pages uses another production hostname, update `ANALYTICS_DASHBOARD_ORIGIN` before deploying the Worker.

Deploy the dashboard after the Worker:

```sh
npx wrangler pages project create tokiri-analytics --production-branch main
npx wrangler pages deploy analytics-dashboard --project-name tokiri-analytics
```

The page asks for the dashboard key at runtime and keeps it in the current browser tab session. Protect the Pages project with Cloudflare Access for the owner's account. The API still checks the separate Worker secret and the exact configured origin. The dashboard is owner diagnostics for the current single user: it shows Action request errors with a plain-language cause, the model/provider or Worker source, and the Worker processing stage; app response time, an estimated combined network/app overhead for Fix and Actions, model-provider time, Worker/ledger time, p95 latency buckets, maximum duration, and requests still active after 10 seconds grouped by whether they are waiting on the provider or Worker/ledger. Only fixed reason and stage codes are retained; raw exception text, selected text, prompts, and model output are not recorded. The app reports only elapsed time and fixed provider/task labels, without text or installation IDs. App-side timing appears after a build containing the reporter. The network estimate is app duration minus Worker duration, so it includes both network directions and local app overhead; it cannot isolate one-way arrival time. Network retries count as separate Worker requests, so one user action can appear more than once. Peek timing is tracked through stream completion. Slow-request counts are recorded at the 10-second threshold while the request is still pending; other timing summaries are recorded when the response completes. The dashboard has no request log or device-level drilldown.

Paddle must deliver `subscription.created`, `subscription.updated`, and `subscription.canceled` to:

```text
https://qwixit-api.levmisiliuk.workers.dev/billing/webhook
```

Never print or commit secret values. Worker logs must not include selected text, model input, or model output. Output validation failures may log only the provider, task, and a fixed reason code.

Set a monthly budget and 50%/80% alerts on each model-provider account used by the Worker; this is the last guard behind rate limits and quotas.

### Deploy order for API changes

`/v2/hotkeygo` is the canonical model endpoint; `/v2/qwix` remains an alias for deployed clients. The client sends a task, selected provider (`openai` or `anthropic`), and enumerated parameters. The Worker owns the prompt (`prompts.js`) and both provider credentials. Provider is optional for old clients and defaults to OpenAI. When a change touches the request or response shape, keep the Worker backward compatible first: deploy a Worker that accepts both the old and the new shape, then ship the app, and remove the old shape only after every installation has updated. Builds from before October 2026 used the removed `/v1/responses` proxy and no longer work.

A prompt change in `prompts.js` needs only a Worker deploy, not an app release. Before deploying one, deploy to a test Worker or accept a brief production window, then run the prompt eval:

```sh
cd cloudflare-worker
npm run eval:prompts                          # production Worker
HOTKEYGO_WORKER_URL=https://… npm run eval:prompts
npm run eval:prompts -- --only peek           # a subset by case name
```

It sends about two dozen synthetic cases through the real model (prompt injection, questions, Ukrainian, surzhyk, slang, code, Markdown, clean text, two pages, Actions presets, Peek translation and summary). It costs model calls, so it is run by hand, not in CI. Each case uses a fresh random installation ID. Every case must pass before a prompt change ships.

## Reset the complete sandbox flow

Initial setup:

```sh
cd cloudflare-worker
npm run setup:reset-test-flow
npm run deploy
```

If the reset secret already exists but the Paddle API key is missing:

```sh
cd cloudflare-worker
npm run setup:paddle-reset
npm run deploy
```

Reset and repeat the full journey:

```sh
cd cloudflare-worker
npm run reset:test-flow
```

The reset cancels matching Paddle sandbox subscriptions before deleting the installation's usage and subscription state. It also clears local preferences, the Keychain installation identity, the running app, and Accessibility permission. Failure to cancel Paddle leaves the ledger intact rather than creating a partial reset.

## Golden release journey

Before a public build, verify this sequence from a clean installation:

1. Install and launch hotkeygo without an existing installation identity.
2. Complete Accessibility onboarding using mouse and keyboard paths.
3. Confirm `⌥⌘X` safely fixes and replaces text in native and browser-backed editors.
4. Confirm `⌥⌘A` transforms and replaces text.
5. Confirm `⌥⌘Z` shows a read-only result and does not replace the source.
6. Consume all 30 free actions and verify that each user action decrements exactly once, including when a retry happens (for example, toggle Wi‑Fi during a Fix) and when Peek's Retry repeats a request.
7. Verify the limit state does not alter selected text and offers the correct upgrade path.
8. Complete Paddle checkout and verify signed webhook activation unlocks Advanced.
9. Relaunch the app and verify subscription restoration from server state.
10. Upgrade a signed Qwixit build with an active sandbox subscription to a signed hotkeygo build; verify that the Keychain installation identity and Advanced access survive the bundle-ID change.
11. Verify cancellation and non-active subscription states return to the intended free behavior.
12. Verify offline, timeout, empty-response, permission, no-selection, and hotkey-conflict recovery.
13. Verify light/dark themes, Reduce Motion, VoiceOver labels, Fix's ⌘V backup, Actions' clipboard restoration, and multi-display panel placement.

## Public `.dmg` readiness

The first public release is not ready until all of the following are resolved:

- Apple Developer Program enrollment and a configured development team
- Developer ID signing with Hardened Runtime
- notarization and stapling
- reproducible `.dmg` packaging and verification on a clean Mac
- production Paddle client token, price, environment, API access, and webhook secret switched together
- production purchase, activation, restoration, cancellation, and refund behavior tested
- privacy policy and customer-facing support/contact path
- a deliberate update strategy
- a deliberate crash-reporting decision that respects the privacy rules in `docs/PRODUCT.md`
- no known critical defects in the golden journey

The current project has an empty development team and the checkout is configured for Paddle sandbox. Treat release configuration as incomplete until those conditions change and the full matrix passes.
