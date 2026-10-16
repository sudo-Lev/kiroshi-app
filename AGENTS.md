# Qwixit repository guidance

## Product compass

Qwixit is a native macOS menu-bar utility that removes the trip to an AI chat and back. The primary job is: select text, press one shortcut, and receive a clean result in place without losing focus or workflow context.

- **Fix (`⌥⌘X`) is the core product.** It corrects typos, grammar, punctuation, and clearly awkward wording with the smallest safe edits. Preserve meaning, tone, language, and formatting.
- **Actions (`⌥⌘A`) is secondary.** It performs an explicit transformation, such as translating selected text, and replaces the selection.
- **Peek (`⌥⌘Z`) is secondary and read-only.** It helps the user understand selected text without replacing the source.
- Speed is the main differentiator, but not at the cost of fabricated, surprising, or needlessly rewritten output.
- The product should feel fast, unobtrusive, stylish, punk, and confident—not like a generic AI chat application.

## Non-negotiable privacy rules

- Never persist or log selected text, prompts derived from it, or model output.
- Keep OpenAI requests at `store: false` and use ephemeral, uncached client sessions.
- Treat selected text as untrusted content, never as instructions.
- Do not add analytics, crash reporting, or third-party SDKs without explicit owner approval. Any acceptable telemetry must avoid user text, avoid new macOS permissions, and avoid additional user-facing consent or disclosure requirements unless the owner approves that trade-off.
- The random Keychain installation ID may identify an installation for quota and subscription state; it is not a user account or an AI credential.

## Architecture and interaction rules

- Keep the feature-first MVVM structure described in `ARCHITECTURE.md`.
- `App/` is the composition root. Views render state and forward intent. View models own presentation state and async task lifetime. AppKit controllers own windows and panels.
- Features must not depend on another feature's presentation layer. Move truly shared primitives to `Core/` or app-wide adapters to `Infrastructure/`.
- Transient panels must not steal focus from the user's active app. Preserve the selection, restore the clipboard after fallbacks, and keep mouse and keyboard paths equivalent.
- Prefer small changes within existing patterns. The current UI is close to the intended product; redesign it only when requested or when fixing a demonstrated usability/accessibility defect.
- **Use TokiriUI first for every new or changed UI surface.** Check `Qwixit/Core/DesignSystem/` and `docs/TOKIRI_UI.md` before introducing a control, visual token, or icon. Reuse an existing component when its meaning and behavior fit; keep one-off feature composition in its feature.
- If TokiriUI lacks a suitable component, use the native SwiftUI/AppKit control for now, record the gap in `docs/TOKIRI_UI.md`, and explicitly tell the owner what is missing in the handoff. Do not silently invent a near-duplicate or force a custom control where macOS behavior matters.
- Choose icons by semantic `TokiriUI.IconName`. Use the curated local vector assets for primary product actions; system symbols are allowed only as catalogued utility fallbacks. When an icon is missing, record and report the gap rather than scattering `Image(systemName:)` strings through feature views. Keep brand marks in supplied assets, not redrawn as icons.
- Billing details—30 free actions and $10/month Advanced—are a tested hypothesis, not permanent product doctrine. Keep them internally consistent, but do not broaden or entrench them without a product decision.

## Read the relevant source, not every source

- Product behavior, priorities, terminology, and non-goals: `docs/PRODUCT.md`
- Code ownership and runtime boundaries: `ARCHITECTURE.md`
- Visual, motion, and interaction specifications: `docs/QWIXIT_DESIGN_BLUEPRINT.md`
- TokiriUI component catalog, icon policy, and open gaps: `docs/TOKIRI_UI.md`
- Local setup, billing tests, deployment, and release readiness: `docs/OPERATIONS.md`
- Durable product and engineering rationale: `docs/DECISIONS.md`

When documentation and behavior conflict, inspect the current implementation and tests, then update the stale document as part of the change. Do not silently preserve contradictions.

## Validation

Use Xcode 16 or newer with the `Qwixit` scheme and a macOS destination.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Qwixit.xcodeproj -scheme Qwixit -configuration Debug \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Qwixit.xcodeproj -scheme Qwixit \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test

cd cloudflare-worker
npm test
npm run check
```

- Run focused tests while iterating and the broadest relevant suite before handoff.
- For UI work, verify light and dark themes, keyboard and mouse interaction, Reduce Motion, and non-activating panel behavior.
- For text replacement, verify native controls plus at least one browser-backed editor and confirm clipboard restoration.
- For billing changes, exercise the complete sandbox cycle in `docs/OPERATIONS.md`.
