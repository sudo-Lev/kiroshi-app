# Qwixit durable decisions

**Last reviewed:** 2026-10-07

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

Qwixit must not persist or log selected text or generated output. Model requests use `store: false`. A random installation ID exists only for quota and subscription state.

**Why:** anonymity and low friction are part of the product value, not merely implementation details.

## D005 — macOS native comes before platform expansion

**Status:** accepted

Qwixit remains a native SwiftUI/AppKit macOS menu-bar application while demand is being validated. Windows, iOS, and browser expansion are deferred.

**Why:** another platform does not repair weak retention or paid demand on the first platform.

## D006 — The current price and allowance are hypotheses

**Status:** provisional

The app currently offers 30 free AI actions per installation per calendar month and $10/month Unlimited.

**Why:** this supports repeated usage, exposes limit behavior, and tests willingness to pay for speed. The numbers may change with evidence.

## D007 — Preserve the current visual identity

**Status:** accepted

The current interface is close to the intended product. Improvements should polish demonstrated problems rather than introduce broad redesigns by default.

**Why:** the desired experience is already largely present: unobtrusive, fast, stylish, punk, and confident.

## D008 — Telemetry has a high adoption bar

**Status:** accepted

Anonymous operational telemetry may be considered only when it excludes user text, avoids new macOS permissions, and does not create surprising consent or disclosure requirements. Any telemetry provider or SDK requires explicit approval.

**Why:** observability is useful, but not at the expense of the anonymity and low-friction promise.

## D009 — Feature-first MVVM without framework ceremony

**Status:** accepted

Use feature-first MVVM in a lightweight Clean Architecture shell. AppKit controllers own windows, view models own presentation state and task lifetime, and protocols isolate system or network effects where testing matters.

**Why:** Qwixit needs explicit ownership for macOS integration without infrastructure disproportionate to a small native utility.
