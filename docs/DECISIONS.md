# hotkeygo durable decisions

**Last reviewed:** 2026-10-16

This is a lightweight decision log. Add an entry when a choice changes product behavior, privacy, architecture, distribution, or the meaning of a core workflow. Temporary implementation details do not need an entry.

## D001 — Fix is the core product

**Status:** accepted

`⌥⌘X` is the shortest path from selected text to a conservative corrected replacement. Actions and Peek may grow, but they must not add friction to Fix.

**Why:** the founding problem is the slow copy/chat/paste loop used to check text.

## D002 — Actions replaces; Peek reads

**Status:** accepted

Actions performs a user-selected transformation and replaces the selection. Peek helps the user understand selected text and remains read-only.

**Why:** replacement is useful when intent is explicit, while reading assistance should not mutate source material.

## D003 — Default correction is conservative

**Status:** accepted

Fix changes typos, grammar, punctuation, and clearly awkward wording using the smallest safe edits. It preserves meaning, tone, language, and formatting.

**Why:** broader rewriting creates validation work and weakens the speed advantage.

## D004 — User text is transient

**Status:** accepted

hotkeygo must not persist or log selected text or generated output in app-controlled storage. Fix's system clipboard backup is specified in D013. Model requests use `store: false`. A random installation ID exists only for quota and subscription state.

**Why:** anonymity and low friction are part of the product value, not merely implementation details.

## D005 — macOS native comes before platform expansion

**Status:** accepted

hotkeygo remains a native SwiftUI/AppKit macOS menu-bar application while demand is being validated. Windows, iOS, and browser expansion are deferred.

**Why:** another platform does not repair weak retention or paid demand on the first platform.

## D006 — The current price and allowance are hypotheses

**Status:** provisional

The app currently offers 30 free AI actions per installation per calendar month and $10/month hotkeygo Advanced. Advanced gives more room to work, not unlimited use: a proposed fair-use ceiling of 300 actions per UTC day and 3 000 per month keeps $10 above model cost. It keeps the same careful Fix quality bar.

**Why:** this supports repeated usage, exposes limit behavior, and tests willingness to pay for speed. The numbers may change with evidence.

## D007 — Preserve the current visual identity

**Status:** accepted

The current interface is close to the intended product. Improvements should polish demonstrated problems rather than introduce broad redesigns by default.

**Why:** the desired experience is already largely present: unobtrusive, fast, stylish, punk, and confident.

## D008 — Telemetry has a high adoption bar

**Status:** accepted

The owner approved first-party Worker diagnostics on 2026-10-23. hotkeygo currently has one user. The Worker stores daily aggregate counts by provider, task, outcome, fixed error reason, and requests still pending after 10 seconds grouped by current phase, plus model-attempt counts, automatic Fix retries, Worker duration, provider duration, and fixed-bucket latency distributions for model requests. The app reports only its elapsed request time plus fixed provider/task labels; the Worker stores those as daily aggregates. For Fix and Actions, app time minus Worker time estimates the combined network trip and app overhead, not a one-way latency. Peek's provider duration and Worker duration cover its streamed response; its end-to-end app time is reported after the stream ends. App-side measurements begin with builds containing the reporter. No installation IDs, IP addresses, selected text, prompts, model output, or text-derived hashes are stored; aggregates expire after 365 days. No third-party SDK or new macOS permission is introduced. Per-installation views and other product-event families require a separate decision.

**Why:** observability is useful, but not at the expense of the anonymity and low-friction promise.

## D009 — Feature-first MVVM without framework ceremony

**Status:** accepted

Use feature-first MVVM in a lightweight Clean Architecture shell. AppKit controllers own windows, view models own presentation state and task lifetime, and protocols isolate system or network effects where testing matters.

**Why:** hotkeygo needs explicit ownership for macOS integration without infrastructure disproportionate to a small native utility.

## D010 — Preview fails closed; Peek never silently truncates

**Status:** accepted

When Preview & Approve is enabled, an unavailable selection snapshot leaves the text unchanged rather than falling back to immediate replacement. Peek rejects selections longer than its request limit with a visible explanation instead of sending only a prefix.

**Why:** both behaviors make the apparent user action match what actually happens to the selected text.

## D011 — Shared dismissal for interactive popups

**Status:** accepted

Interactive transient panels use the shared HotkeyGoUI close badge and close with `⌥⌘X`. That binding remains reserved when the user changes the Fix shortcut, so Actions and Peek cannot be assigned it. The menu-bar popover is the exception: its close badge shows the configured Fix shortcut, and pressing Fix closes that popover while it is open. The three feature shortcuts must stay unique. Closing a preview cancels it without replacing text; click-through status notices and standard macOS windows keep their current behavior.

**Why:** transient panels keep a predictable shared dismissal gesture, while the menu-bar popover's shortcut badge stays in sync with the user's Fix setting.

## D012 — Use one paste path across apps

**Status:** accepted

Fix and Actions capture selected text and source focus, restore that focus, and replace through the clipboard plus ⌘V. Accessibility may capture selection and restore focus, but it does not write replacement text or gate success on editor readback. D013 updates Fix's completion label and clipboard behavior.

**Why:** editor Accessibility behavior varies and can be delayed or report success without updating the real input. One keyboard-based path avoids app-specific replacement branches and makes status claims match what hotkeygo can observe reliably.

## D013 — Keep a manual paste backup after Fix

**Status:** accepted

After Fix posts ⌘V, leave the generated replacement on the system clipboard. Show the compact green success chip for the completed Fix request. Success does not assert that the destination editor consumed the paste. Selection-copy fallbacks and Actions continue restoring the previous clipboard, and a newer clipboard change is never overwritten.

**Why:** some editors miss a synthetic paste event. The user can press ⌘V immediately without reopening hotkeygo or losing the generated correction.

## D014 — The Worker owns prompts; one action costs one attempt

**Status:** accepted

The app sends a task (`fix`, `action`, `peek`), the selected text, the user's enumerated provider choice, and task parameters. It never sends instructions or provider credentials. The source Worker serves this contract at `/v2/hotkeygo` and keeps `/v2/qwix` as a deployment-compatibility alias; the app stays on `/v2/qwix` until the renamed route is deployed. The Worker owns provider routing and prompts in `cloudflare-worker/prompts.js`, so prompt or provider changes ship with a Worker deploy. Every retry of one user action carries the same operation ID, and the ledger charges it once. Confirmed service failures, rejected results, and a Fix with nothing to change return the action, each capped per day. Actions has no quick-questions step and no free-form panel follow-up.

**Why:** any client-built prompt can be replayed with arbitrary instructions, turning the free allowance into a free general-purpose chatbot. Charging per HTTP request made flaky networks cost users several actions for one result.
