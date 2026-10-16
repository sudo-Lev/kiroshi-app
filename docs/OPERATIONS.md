# Qwixit operations and release guide

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

Open `Qwixit.xcodeproj`, select the `Qwixit` scheme and **My Mac**, then run with `⌘R`.

For an unsigned command-line build:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Qwixit.xcodeproj \
  -scheme Qwixit \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/QwixitDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  build
```

Run the unit tests with:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Qwixit.xcodeproj \
  -scheme Qwixit \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/QwixitDerivedData \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO \
  test
```

Do not launch an additional app process casually during automated verification: single-instance coordination can terminate the instance the owner is actively testing.

### Replacement reliability check

Fix and Actions use one replacement path in every app: capture the selected text and source focus, restore the source app and focused element, put the fresh text on the clipboard, then post ⌘V. AX is used to read the selection and restore focus; it never writes the replacement or decides whether a paste succeeded. Actions' insert mode sends Right Arrow first to collapse the selection at its end, then uses the same paste path.

ReplacementAttemptReport contains only three transient steps: clipboard write, optional caret move, and ⌘V event. isSubmitted means the clipboard write completed and the required keyboard events were posted. The UI says “Paste sent”; this is an honest report of the action Tokiri took, not proof that another app consumed the event. If Tokiri cannot prepare the clipboard or post the required event, it offers the fresh text and a manual copy button. The clipboard is restored after the paste when it still contains Tokiri's temporary value. No selected or generated text is logged or persisted.

Unit tests cover the clipboard, paste-event, and caret-move requirements for a submitted status, plus recovery when a paste event cannot be posted. Clipboard archive tests verify rich clipboard restoration and preserve newer clipboard content. These tests do not measure delivery to real editors. Before claiming a replacement success rate, use controlled, unsent drafts in a native text control and browser editors such as Slack and GitHub, plus representative spreadsheet and messaging apps. Exercise single-line, multiline, and repeated selections; Fix, Actions replace, and Actions insert; and confirm the clipboard is restored after each attempt. Record only pass/fail and editor category. A 99.5% delivery claim requires a sufficiently large real-editor trial; unit tests alone cannot support it.

## Worker checks

The Worker lives in `cloudflare-worker/`.

```sh
cd cloudflare-worker
npm install
npm test
npm run check
```

It proxies model requests, enforces monthly usage atomically with a Durable Object, exposes billing state, receives signed Paddle webhooks, and hosts the checkout and activation pages.

Required production-like bindings and secrets:

- `USAGE_LEDGER` Durable Object binding
- `OPENAI_API_KEY`
- `PADDLE_WEBHOOK_SECRET`

Development reset additionally needs:

- `DEVELOPMENT_RESET_SECRET`
- `PADDLE_API_KEY` with sandbox subscription read/write access

## Deploy the Worker

```sh
cd cloudflare-worker
npx wrangler secret put OPENAI_API_KEY
npx wrangler secret put PADDLE_WEBHOOK_SECRET
npm run deploy
```

Paddle must deliver `subscription.created`, `subscription.updated`, and `subscription.canceled` to:

```text
https://qwixit-api.levmisiliuk.workers.dev/billing/webhook
```

Never print or commit secret values. Worker logs must not include selected text, model input, or model output.

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

1. Install and launch Qwixit without an existing installation identity.
2. Complete Accessibility onboarding using mouse and keyboard paths.
3. Confirm `⌥⌘X` safely fixes and replaces text in native and browser-backed editors.
4. Confirm `⌥⌘A` transforms and replaces text.
5. Confirm `⌥⌘Z` shows a read-only result and does not replace the source.
6. Consume all 30 free actions and verify that each server-authorized request decrements exactly once.
7. Verify the limit state does not alter selected text and offers the correct upgrade path.
8. Complete Paddle checkout and verify signed webhook activation unlocks Advanced.
9. Relaunch the app and verify subscription restoration from server state.
10. Verify cancellation and non-active subscription states return to the intended free behavior.
11. Verify offline, timeout, empty-response, permission, no-selection, and hotkey-conflict recovery.
12. Verify light/dark themes, Reduce Motion, VoiceOver labels, clipboard restoration, and multi-display panel placement.

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
