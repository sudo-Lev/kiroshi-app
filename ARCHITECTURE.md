# Qwixit architecture

**Last reviewed:** 2026-10-16

Qwixit is a native macOS 13+ menu-bar utility built with SwiftUI and AppKit. It uses feature-first MVVM inside a lightweight Clean Architecture shell: enough separation to make system integrations testable, without adding framework ceremony to a small application.

## System boundary

```text
Active macOS app
    ↕ Accessibility API / clipboard fallback
Qwixit macOS app
    ↕ HTTPS + installation ID
Cloudflare Worker
    ├── OpenAI Responses API
    ├── Durable Object usage/subscription ledger
    └── Paddle checkout + signed webhooks
```

The macOS client owns selection capture, UI, focus restoration, and replacement. The Worker owns model credentials, request policy, monthly authorization, and the subscription source of truth. Paddle webhooks—not client claims—activate Advanced.

## Repository layout

- `Qwixit/App/` — composition root, application lifecycle, status item, global hotkey routing, and top-level window ownership.
- `Qwixit/Core/DesignSystem/` — TokiriUI tokens, semantic icons, reusable controls, and presentation primitives without feature-specific behavior. The current implementation is app-local, not a separate CDN or package.
- `Qwixit/Infrastructure/` — app-wide adapters for Accessibility, billing, hotkeys, networking, persistence, and migration.
- `Qwixit/Features/<Feature>/Domain/` — feature language, pure models, and dependency contracts.
- `Qwixit/Features/<Feature>/Data/` — concrete data access and external API implementations.
- `Qwixit/Features/<Feature>/Services/` — focused platform or orchestration helpers local to one feature.
- `Qwixit/Features/<Feature>/Presentation/` — SwiftUI views, observable view models, and AppKit window/panel controllers.
- `QwixitTests/` — Swift unit tests organized by feature.
- `cloudflare-worker/` — Worker implementation, Durable Object, Paddle integration, reset tooling, and Node tests.

Not every feature needs every layer. Create a folder only when code genuinely belongs there.

## Dependency direction

```text
Presentation → Domain ← Data / Infrastructure
          App chooses concrete implementations
```

- Views render state and forward user intent to a view model.
- View models own presentation state and retain/cancel asynchronous work.
- Effects crossing a process or platform boundary use protocols where isolation improves testing.
- Data and infrastructure types implement those protocols.
- `App` normally chooses concrete implementations and connects feature entry points.
- A feature must not reach into another feature's presentation layer. Shared behavior moves to `Core` or an app-wide infrastructure contract.
- Feature views use TokiriUI for matching controls and icons. A missing primitive is documented in `docs/TOKIRI_UI.md`; native SwiftUI/AppKit is the temporary fallback, with the gap called out to the owner. TokiriUI owns appearance and interaction primitives, not view-model state, business rules, or AppKit window lifecycles.

## Composition and lifecycle

`QwixitApp.swift` is the composition root. `AppContainer` constructs long-lived services, feature view models, and panel controllers. `AppDelegate` coordinates:

- single-instance startup;
- menu-bar status item and popover;
- onboarding and settings windows;
- global Fix, Actions, and Peek hotkeys;
- shared popup dismissal routing: a visible interactive popup consumes `⌥⌘X` before Fix, while each AppKit controller retains ownership of its close behavior;
- launch/activation refreshes;
- teardown of tasks and hotkey registrations.

AppKit objects owning windows or panels end in `WindowController` or `PanelController`. They remain outside feature view models because window level, activation, focus, Spaces behavior, placement, and event monitors are platform concerns.

## Core runtime flows

### Fix (`⌥⌘X`)

1. `AppDelegate` receives the Carbon hotkey without activating Qwixit.
2. `QuickImproveViewModel` verifies Accessibility access and captures the selected text and its screen bounds.
3. `TextImprovementService` sends a `fix` task through `OpenAIClient`. Selections over 6 000 characters are rejected first with the `TOO LONG` chip, without a request.
4. The Worker atomically authorizes usage, builds the prompt, and checks the result (see Worker request API). If Fix finds nothing to change, Qwixit shows `ALREADY CLEAN` and touches neither the selection nor the clipboard, in either mode.
5. In the default mode, Qwixit restores focus and sends the replacement through the shared clipboard paste path. With **Preview & Approve** enabled, it keeps a transient selection snapshot and proposed output in memory, shows an anchored review panel, and sends the paste only after the user approves it. If a reviewable snapshot cannot be captured, it reports an error instead of replacing immediately. After a Fix paste attempt, the replacement remains on the system clipboard for manual ⌘V.
6. The feedback controller reports processing, success, limit, permission, connectivity, or failure. Success means the result was prepared and the paste event was posted; the note above it offers ⌘V if the text is missing. Esc or Keep original leaves the source text unchanged. A posted paste event is not proof that the destination editor accepted it.

The original text must remain unchanged whenever capture, authorization, or model output fails. If the paste cannot be sent, the recovery panel offers the result for manual copying.

### Actions (`⌥⌘A`)

1. The independent Actions hotkey opens `PalettePanelController` beside the selection.
2. `PaletteViewModel` exposes the presets (translate, Slack style, make formal) and keyboard selection state. Typed search text only filters; it never reaches the model.
3. The chosen preset runs as an `action` task through the same metered service boundary.
4. A successful action replaces the selection; failures leave it unchanged.

Actions is a replacing flow. It must stay independent from the Fix hotkey and must not depend on double-tap timing.

### Peek (`⌥⌘Z`)

1. `PeekHotkey` triggers selection reading.
2. `PeekPanelController` opens a non-activating reading surface.
3. `PeekViewModel` chooses or executes translation/summary behavior through `PeekClient`.
4. Results remain in the panel for reading or copying; Peek never automatically replaces source text.
5. Selections exceeding the request limit receive a visible error; Peek never silently translates or summarizes only a prefix.

### Worker request API

`POST /v2/qwix` accepts only a task and enumerated parameters, never instructions:

```json
{ "task": "fix", "text": "…" }
{ "task": "action", "text": "…", "action": "translate", "language": "uk" }
{ "task": "peek", "text": "…", "mode": "translate", "language": "uk", "sourceLanguage": "pl" }
```

`action` is `translate`, `slack`, or `formal`; Peek `mode` is `translate` or `summary` with `length` `tldr`, `points`, or `full`; languages are short language codes; `priority: true` is honored only for Advanced. Unknown tasks or fields return `400 invalid_task`; text above 6 000 characters returns `413 text_too_long` before any charge. `cloudflare-worker/prompts.js` builds every prompt and wraps the selection in `<selected_text>` tags, escaping lookalike tags inside it.

Fix and Actions are not streamed so the Worker can check the result first: status `completed`, non-empty, no wrapper tags, and a plausible length ratio (Fix 0.6–1.5, translate 0.4–2.5, Slack/formal 0.1–2.0, always ±40 characters). A failed check refunds the action and returns `422 output_rejected`. Fix answers with the `qwixit_fix` schema; a `clean` verdict, or a "fix" identical after NFC, line-ending, and edge-whitespace normalization, returns `{ "result": "clean" }` and refunds the action (at most 20 per UTC day). Otherwise Fix returns `{ "result": "fixed", "text": "…" }` and Actions `{ "text": "…" }`. Peek keeps streaming. Responses and `/billing/status` report the plan as `advanced` or `free`; for Advanced, `X-Qwixit-Remaining` is today's remaining actions. `/v2/qwix` is the only model endpoint: the legacy `/v1/responses` proxy, which accepted client instructions, is removed.

### Billing and quota

1. Each installation gets a random identifier stored in Keychain.
2. The client attaches it as `X-Qwixit-Installation-ID`; it is not a user credential.
3. A Durable Object serializes usage authorization and maintains the current UTC-month count and subscription state.
4. Active Paddle subscription statuses bypass the free allowance.
5. Paddle signs webhook events; the Worker verifies the signature and deduplicates event IDs before updating subscription state.
6. The client caches display state, but the server ledger remains authoritative.
7. One user action is charged once. `NetworkRetry` creates a UUID before the first attempt and sends it as `X-Qwixit-Operation-ID` on every retry; Peek keeps one ID per panel request and reuses it for Retry. The ledger stores only `op:<id> → {state, attempts, createdAt}` (no text or text hash), allows at most 3 attempts within 15 minutes (`409 operation_exhausted` after that, without calling OpenAI), and removes records older than an hour with a Durable Object alarm.
8. When OpenAI is unreachable or answers 5xx/429, the Worker refunds the operation (`502 upstream_failed`), capped at 20 refunds per installation per UTC day. A retry of a refunded operation charges again, so a successful action always costs exactly one. The header is required; the ledger refuses to charge without it.
9. Advanced is capped at 300 actions per UTC day and 3 000 per UTC month (`429 daily_limit` / `monthly_limit`); these are a billing hypothesis, not doctrine. Per-minute Rate Limiting bindings guard each installation (20) and IP (60) with `429 rate_limited` and `Retry-After`.
10. Client retries cover connectivity errors, 408/425/5xx, and 429 after `Retry-After` (backoff 1 s, then 2 s). Incomplete or empty output, 402, 409, and other 4xx are not retried. The session times out after 30 s without data and 60 s per request.

## Focus, selection, and clipboard invariants

- Transient panels are non-activating and must not become the main application window.
- Prefer Accessibility reads for selection capture, with a clipboard copy fallback when needed. Fix and Actions replace through paste rather than Accessibility writes.
- Clipboard operations share one transaction gate across features. Snapshot the complete previous pasteboard. Restore it after selection-copy fallbacks and Actions unless another process changed the clipboard meanwhile. Fix leaves its replacement for manual ⌘V after a successful clipboard write; never overwrite newer content from another process.
- Restore focus to the originating application before replacement.
- Keep panels inside the visible screen and avoid covering the selected text when adjacent placement exists.
- Do not recreate or repeatedly show a visible panel in response to its own state updates.

These invariants are core behavior, not cosmetic implementation details.

## Privacy and security boundaries

- Do not persist or log selected text or model output in app-controlled storage. Fix intentionally leaves its generated replacement on the system clipboard for manual ⌘V.
- The app uses ephemeral URL sessions without a URL cache.
- The client and Worker both force OpenAI `store: false`.
- Selected text is wrapped as data and explicitly treated as untrusted instructions.
- Model API credentials and Paddle webhook secrets exist only as Worker secrets.
- Subscription activation is accepted only from verified Paddle webhooks.
- Reset endpoints require a dedicated bearer secret and are development tooling, not a customer API.

## Persistence

- `UserDefaults` stores preferences, onboarding state, developer scenarios, and cached quota display state.
- Keychain stores the random installation identity and local development-reset secrets.
- The Durable Object stores authoritative usage, subscription, and webhook-deduplication state per installation.
- No persistence layer may store selected text or generated output.

## Naming and ownership

- Observable presentation models end in `ViewModel`, not `Store`.
- Window owners end in `WindowController`; transient panel owners end in `PanelController`.
- Global settings live in `SettingsViewModel`; one-shot correction state lives in `QuickImproveViewModel`.
- Expose read-only state unless mutation is a genuine user-editable binding.
- Retain long-running `Task` instances and cancel them when their owner stops or supersedes the work.

## Testing strategy

- View-model tests use protocol fakes and assert state transitions plus requested effects.
- Domain logic is tested without SwiftUI or AppKit where possible.
- Infrastructure tests cover serialization, hotkey registration behavior, language targeting, quota, webhook security, and boundary failures.
- Worker tests cover server-enforced request policy, `/v2/qwix` task validation and output checks, atomic allowance behavior, Paddle signature verification, subscription transitions, and safe reset semantics.
- App composition receives a build smoke test so missing wiring is caught.
- Manual validation covers Accessibility, focus, browser-backed editors, Fix's clipboard backup, Actions' clipboard restoration, keyboard/mouse parity, themes, Reduce Motion, VoiceOver, and multiple displays.

## Review checklist

Before adding code, verify:

- the file sits under the owning feature and layer;
- dependencies still point inward;
- cross-boundary effects are injectable where testing matters;
- no selected text or output can reach logs or durable storage;
- the change preserves focus, the appropriate clipboard behavior for each feature, and unchanged-on-failure guarantees;
- UI changes preserve the product hierarchy and do not add generic AI-chat patterns;
- billing changes preserve server authority and signed webhook activation;
- relevant documentation and tests change with behavior.
