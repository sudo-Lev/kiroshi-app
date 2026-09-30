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
- Three-step first-run onboarding
- Focused settings for feedback, Accessibility access, and the OpenAI connection
- Reduced-motion-compatible SwiftUI animations

Without an API key, `TextImprovementService` uses a deterministic local demo implementation. Add an `sk-…` key in **Settings → OpenAI Connection** to switch automatically to the OpenAI Responses API. The key is stored in macOS Keychain, requests use `store: false`, and secrets are never written to app preferences or logs.

For development-only runs, Qwixit also reads `OPENAI_API_KEY` from the Xcode scheme’s **Run → Arguments → Environment Variables**. Do not commit a real key or bundle a `.env` file with the app.

## Project structure

- `AppViewModel.swift` owns explicit presentation state and coordinates the improve-and-replace workflow.
- `QwixitApp.swift` is the composition root that injects live service implementations into the app-scoped view model.
- `Services/` contains protocol-backed system integrations and the OpenAI client.
- `Views/` render view-model state and forward user intents; transient animation state stays local to each view.
- `DesignSystem.swift` contains the shared compact dark visual vocabulary.

The app follows MVVM with dependency direction `View → AppViewModel → service protocols`. Async improvement and permission tasks are owned and cancelled by the view model, while AppKit window and application lifecycle work remains in the composition root.
