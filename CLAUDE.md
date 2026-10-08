# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

The canonical agent guidance lives in `AGENTS.md` (product compass, privacy rules, architecture rules, validation). Follow it; this file only adds what it leaves out.

@AGENTS.md

## Commands

Build and full test commands are in `AGENTS.md`. Narrower variants:

```sh
# One Swift test class or method (XCTest, target QwixitTests)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Qwixit.xcodeproj -scheme Qwixit -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO test \
  -only-testing:QwixitTests/PeekViewModelTests/testSomething

# One Worker test by name (node:test)
cd cloudflare-worker && node --test --test-name-pattern "Paddle signatures" worker.test.js
```

Run the app from Xcode (`⌘R`). Launching a new build closes any older running Qwixit instance (single-instance per bundle ID). Accessibility permission is required for selection capture and replacement.

## Code-name ↔ product-name map

Folder names don't match the product terms used in docs:

| Product term | Hotkey | Code |
| --- | --- | --- |
| Fix | `⌥⌘X` | `Features/QuickImprove/` (`QuickImproveViewModel`, `TextImprovementService`) |
| Actions | `⌥⌘A` | `Features/Palette/` (`PaletteViewModel`, `PalettePanelController`) |
| Peek | `⌥⌘Z` | `Features/Peek/` (`PeekViewModel`, `PeekPanelController`, `PeekClient`) |
| Onboarding / settings | — | `Features/Settings/` |

## Big picture

- `Qwixit/App/QwixitApp.swift` is the composition root: `AppContainer` builds services, view models, and panel controllers; `AppDelegate` owns the status item, hotkey routing, windows, and teardown.
- All model calls go through `cloudflare-worker/worker.js` (a single-file Worker). It holds the OpenAI key, enforces model policy and `store: false`, and meters every request through a Durable Object ledger keyed by the `X-Qwixit-Installation-ID` header. Paddle signed webhooks are the only path to Unlimited. Changes to request shape usually touch both the Swift networking layer and the Worker.
- Naming conventions: presentation models end in `ViewModel` (never `Store`); window owners end in `WindowController`, transient non-activating panels in `PanelController`.
- On any failure (capture, quota, model, replacement) the user's original selection must stay unchanged; clipboard fallbacks must snapshot and fully restore the pasteboard.

See `ARCHITECTURE.md` for the full runtime flows and review checklist, and `README.md` / `docs/OPERATIONS.md` for Worker deployment and the sandbox billing reset flow (`npm run reset:test-flow`).
