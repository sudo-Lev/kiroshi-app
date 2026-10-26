# hotkeygo product knowledge

**Status:** product source of truth
**Last reviewed:** 2026-10-16

## Product promise

hotkeygo makes working with selected text faster than leaving the current app for ChatGPT, Claude, DeepSeek, or a translator.

The problem is not access to AI. The problem is the workflow:

1. write or encounter text;
2. copy it;
3. open an AI chat or translator;
4. paste and explain the task;
5. wait;
6. copy the result;
7. return to the original app;
8. paste it back.

hotkeygo collapses that sequence into a selection and a shortcut. The product sells speed, a new workflow, and the absence of friction—not merely access to a model.

## Target user

The first target user is someone with the founder's own recurring pain: they write across macOS, are unsure whether a sentence contains mistakes, or regularly need to translate text, and currently interrupt their work to use a general-purpose AI chat.

This is deliberately founder-led rather than a fabricated broad persona. Wider platform expansion should follow evidence of meaningful macOS demand, not precede it.

## Product hierarchy

### 1. Fix — the core

Default shortcut: **Option + Command + X**. The user can change it in Settings.

Fix replaces selected text in place. For the current product stage it should:

- correct typos, grammar, punctuation, and clearly awkward wording;
- make the smallest safe edits;
- preserve meaning, voice, language, intent, and formatting;
- avoid adding facts, changing claims, or turning the text into generic AI prose;
- complete with minimal interruption and no trip to another app.

The default Fix behavior remains immediate replacement. An optional **Preview & Approve** setting can keep the original selection unchanged, show the proposed correction with a local diff, and wait for explicit approval before applying it. If preview cannot safely capture the selection, it leaves the text unchanged and explains why.

The default shortcuts are Fix **Option + Command + X**, Actions **Option + Command + A**, and Peek **Option + Command + Z**. Users can record a different key combination for each action in Settings; combinations must be unique. **Option + Command + X** remains reserved as the shared close shortcut for interactive transient popups. The menu-bar popover's close badge shows the configured Fix shortcut, and that shortcut closes the menu-bar popover while it is open. When Fix keeps its default shortcut, the shared dismissal takes priority while any interactive popup is open. After Fix is remapped, its shortcut closes the menu-bar popover, and **Option + Command + X** remains the shared dismissal shortcut for transient popups. Onboarding teaches the current Fix, Actions, and Peek shortcuts.

The long-term aspiration is a highly intelligent assistant that understands what the user meant. Until quality can be validated confidently, conservative correction is preferred over ambitious rewriting.

### 2. Actions — explicit transformations

Default shortcut: **Option + Command + A**. The user can change it in Settings.

Actions handles an intentional transformation and replaces the selected text. The primary example is writing in Ukrainian and translating directly to English. The user explicitly chooses the transformation, so the boundary is clearer than automatic rewriting.

Actions is useful, but it must not make the core Fix path slower or more complicated.

### 3. Peek — read without changing

Default shortcut: **Option + Command + Z**. The user can change it in Settings.

Peek is for text the user is reading and does not understand. It shows a translation or explanation without replacing the source text. Peek is the fast alternative to opening a translator or AI chat while reading.

If the selection exceeds what Peek can process, show a clear length error instead of presenting a result for an undisclosed excerpt.

The durable boundary is simple:

- Actions transforms and replaces.
- Peek helps the user understand and remains read-only.

## Experience principles

1. **Speed comes first.** Every unnecessary window, confirmation, click, and focus change weakens the product.
2. **Clean output earns trust.** Fast nonsense is not useful. Ambitious transformations require an explicit user action.
3. **Stay out of the way.** hotkeygo should live quietly on the computer and appear only when invoked or when a real recovery action is necessary.
4. **Selected text remains central.** Preserve the user's place, selection, and active application. Restore the clipboard after capture fallbacks and Actions; Fix leaves its result there as a manual paste backup.
5. **Keyboard first, never keyboard only.** Core workflows must be fast from the keyboard, while every visible action remains genuinely clickable and accessible.
6. **Confident personality, restrained footprint.** The product may feel stylish, punk, and bold without becoming loud, decorative, or attention-seeking.
7. **No generic AI theater.** Avoid chat chrome, verbose model narration, magical claims, and unnecessary assistant personality.

## Privacy position

hotkeygo is built around speed and anonymity.

- Selected text and generated output must not be persisted or logged in hotkeygo storage. Fix intentionally leaves the generated replacement on the system clipboard so the user can press ⌘V if the automatic paste is missing.
- OpenAI requests use `store: false`.
- The app offers GPT-5.6 Luna and Claude Haiku 5.5. It sends the selected text only to the provider the user chose; provider credentials stay in Cloudflare Worker secrets. Claude requests use structured outputs, which Anthropic documents as zero data retention for prompts and responses (the schema may be cached for up to 24 hours).
- hotkeygo currently has no user account. A random device-local installation ID exists only to enforce quota and associate subscription state.
- The owner approved internal operational analytics on 2026-10-23. hotkeygo currently has one user, so the dashboard is for owner diagnostics: Action request errors, request outcomes, app response time, the combined network/app overhead for Fix and Actions, model-provider time, Worker/ledger time, and requests still pending after 10 seconds. The Worker stores daily aggregates by UTC day, provider, task, outcome, fixed error reason, and slow-request phase; the app reports only elapsed time with fixed provider/task labels. The Fix and Actions network estimate is app time minus Worker time, so it combines both network directions and app overhead; it cannot isolate one-way latency. Peek is streamed, so its app and Worker timings run through stream completion. App-side measurements begin with builds containing the reporter. No installation IDs, IP addresses, selected text, prompts, model output, or text-derived hashes are stored; daily aggregates expire after 365 days. Other event families or per-installation views need a separate product decision.

## Business model

The current model is 30 free AI actions per installation per calendar month and $10/month for hotkeygo Advanced. Advanced gives more room to work, with a fair-use ceiling (proposed: 300 actions per UTC day, 3 000 per month), while keeping the same careful Fix quality bar. Fix, Actions, and Peek accept up to about 2 pages (6 000 characters); longer selections are rejected in the app before any request. This is a working hypothesis with several purposes:

- let the app remain installed and useful without immediate payment;
- expose natural usage and limit behavior;
- test whether users will pay for the faster workflow;
- support the service cost if the product gains traction.

The exact allowance, price, and packaging may change. Do not treat them as the product's identity.

## Current stage and priorities

hotkeygo is preparing for its first public macOS distribution. The immediate priority is to harden the complete commercial flow:

`install → onboard → use 30 actions → reach limit → subscribe → unlock Advanced → restore state`

The next release milestones are:

1. remove critical defects from the app, text-replacement workflow, quota, and subscription lifecycle;
2. replace Paddle sandbox configuration with a verified production payment flow;
3. enroll in the Apple Developer Program and configure production signing and notarization;
4. produce a trustworthy downloadable `.dmg`;
5. establish an update and support path appropriate for a public app.

## Near-term non-goals

- Building Windows, iOS, or browser versions before macOS demand is validated.
- Becoming a general-purpose AI chat application.
- Aggressively rewriting the user's voice through the default Fix action.
- Adding features that increase surface area without strengthening the core workflow.
- Replacing the current visual system wholesale; it is close to the intended product and should evolve deliberately.

## Open hypotheses

- Whether the market values the workflow enough to support a paid product.
- Whether 30 free actions and $10/month produce the right activation and conversion behavior.
- Which anonymous operational signals, if any, provide enough value to justify implementation and disclosure.
- Whether platform expansion would matter after macOS retention and paid demand are known.
