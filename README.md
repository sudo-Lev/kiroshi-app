# Qwixit

**Don't rewrite it. Qwixit.** You keep writing. Qwixit keeps up.

Qwixit is a native macOS menu-bar utility built with SwiftUI and AppKit. Select text in any application, press `⌥⌘X`, and Qwixit replaces the selection without taking focus away from the active app.

## Run

1. Open `Qwixit.xcodeproj` in Xcode 16 or newer.
2. Select the **Qwixit** scheme and **My Mac**.
3. Run the app.
4. Complete onboarding and grant Accessibility access when macOS asks.

Use **Product → Run** (`⌘R`) each time you want to start the local build. Qwixit enforces one running process per bundle identifier: launching from Xcode automatically closes an older Qwixit instance before registering the global shortcut and showing feedback. You may need to quit an older pre-fix build manually once from its menu-bar window or Activity Monitor.

The project targets macOS 14 and has App Sandbox disabled because global Accessibility replacement and Carbon hotkeys require system-wide access. For distribution, sign and notarize the app with your Developer ID.

## What it does

- Native menu-bar app lifecycle (`LSUIElement`)
- Global `⌥⌘X` hotkey (`⌥⌘X` twice opens Translate, Slack style, and Make formal; `⌥⌘Z` opens Peek)
- Accessibility-based selection reading and in-place replacement
- Copy/paste fallbacks for web-backed editors, with full clipboard restoration
- Non-activating feedback near the selected text
- Processing, success, no-selection, permission, and error states
- Three playable onboarding levels plus an Accessibility unlock step
- Focused settings for feedback and Accessibility access
- Reduced-motion-compatible SwiftUI animations

Qwixit includes 30 free AI actions per installation each calendar month. An active Unlimited subscription is $10/month and removes that limit. Every model request is counted server-side, including Quick Fix, palette actions, Peek translation/summary, and AI-generated refinement questions.

Requests go through the Cloudflare Worker at `qwixit-api.levmisiliuk.workers.dev`; users do not configure or receive an OpenAI API key. The app keeps a random installation identity in macOS Keychain. A Durable Object atomically enforces the monthly quota, while signed Paddle webhooks are the only way to activate Unlimited access. OpenAI requests use `store: false`.

## Worker deployment

The Worker lives in `cloudflare-worker/` and requires the `USAGE_LEDGER` Durable Object binding from `wrangler.toml` plus two encrypted secrets:

```sh
cd cloudflare-worker
npx wrangler secret put OPENAI_API_KEY
npx wrangler secret put PADDLE_WEBHOOK_SECRET
npx wrangler deploy
```

Configure Paddle to send `subscription.created`, `subscription.updated`, and `subscription.canceled` events to `https://qwixit-api.levmisiliuk.workers.dev/billing/webhook`. The checkout is currently wired to the Paddle sandbox; switch the client token, price ID, Paddle environment, and webhook secret together before a production release.

### Reset the complete test flow

The development reset cancels the current Paddle sandbox subscription immediately, removes the installation's Durable Object data (usage, subscription, and processed webhook IDs), stops the local app, clears current and legacy preferences, removes the installation ID from Keychain, and resets Accessibility permission. The next Debug launch creates a genuinely new installation.

Configure a separate reset secret once and deploy the Worker. The setup command generates the reset secret, uploads it with Wrangler, keeps the local copy in macOS Keychain, and then asks for a sandbox Paddle API key with **Subscription Read and Write** permissions. Read access lets reset find every sandbox subscription attached to the installation, including one orphaned by an older reset:

```sh
cd cloudflare-worker
npm run setup:reset-test-flow
npm run deploy
```

If the reset secret was configured with an earlier version, add only the missing Paddle key and redeploy:

```sh
cd cloudflare-worker
npm run setup:paddle-reset
npm run deploy
```

Then restart the complete flow whenever needed:

```sh
cd cloudflare-worker
npm run reset:test-flow
```

Run the Debug build again. It starts at welcome/onboarding with a new installation identity, 30 free actions, no active subscription, and a fresh Accessibility permission step. The reset fails without changing the ledger if Paddle cancellation cannot be completed; the endpoint returns 404 when the Worker secret is not configured and rejects requests without the matching bearer token.

## Project structure

- `AppViewModel.swift` owns explicit presentation state and coordinates the improve-and-replace workflow.
- `QwixitApp.swift` is the composition root that injects live service implementations into the app-scoped view model.
- `Services/` contains protocol-backed system integrations and the OpenAI client.
- `Views/` render view-model state and forward user intents; transient animation state stays local to each view.
- `DesignSystem.swift` contains the shared compact dark visual vocabulary.

The app follows MVVM with dependency direction `View → AppViewModel → service protocols`. Async improvement and permission tasks are owned and cancelled by the view model, while AppKit window and application lifecycle work remains in the composition root.
