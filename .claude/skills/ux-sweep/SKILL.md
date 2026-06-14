---
name: ux-sweep
description: Run a UX sweep on one feature of the Daccord Flutter client — audit it for simplicity and consistency across desktop and mobile, benchmarked against Discord and other popular chat apps, then report ranked findings with fixes. Use when the user asks to "UX sweep", "UX review", "audit the UX of", "polish", or "review the design/usability" of a feature (messaging, voice, channels, spaces, member, settings, profiles, authentication, admin, server, events, notifications, user, developer, updates). Code-first, then confirmed live on real viewports.
---

# UX Sweep

Audit **one feature** of this Flutter/Dart Daccord client for **simplicity** and **consistency**, on **both desktop and mobile**, judged against the conventions of **Discord and other mature chat apps** (Slack, Telegram, Element). Produce a ranked, actionable findings report — not a rewrite.

The argument is the feature to sweep. If none was given, ask which one (offer the modules under `lib/features/`). Sweep exactly one feature per run; if asked for several, do them sequentially and report each separately.

## What "good" means here

Three lenses, applied to every screen and flow:

1. **Simplicity** — the obvious thing is easy; rare/destructive things don't crowd the common path. Minimal taps to the primary action. No redundant controls, dead affordances, or settings that should be defaults. Empty/loading/error states are handled and calm.
2. **Consistency** — same concept looks and behaves the same everywhere: spacing, typography, iconography, button hierarchy, hover/press/focus states, context-menu contents, terminology (use **Accord** vocab — Space, Channel, Member, Role — never Discord's "Guild/Server"). Matches patterns already established in *other* features of this app. Reuses `lib/shared/components/` rather than reinventing.
3. **Chat-app conventions** — does the interaction match what users already expect from Discord et al.? Message hover actions, reply/edit/react affordances, unread indicators, mention/typing/presence cues, drag-to-reorder, right-click context menus on desktop, long-press + bottom sheets on mobile, swipe gestures. Deviate only when there's a reason; flag unjustified novelty as a cost.

Mobile and desktop are **not** the same audit. The app switches layout at a **720px width breakpoint** (`_wideLayoutBreakpoint` in `accord_home.dart`, mirrored in `voice_view.dart`). Below it: single-pane, drawer nav, touch targets ≥44px, gestures, bottom sheets. Above it: multi-pane, hover states, right-click menus, keyboard shortcuts. Every finding must say which surface(s) it applies to.

## Phase 1 — Code-first analysis

Map the feature before looking at it running.

1. Read the feature module top to bottom: `lib/features/<feature>/{views,components,controllers,repositories,models}/`. Note every screen, dialog, sheet, and the user flows that reach them.
2. For each surface, check the three lenses above against the code: Does it use `MediaQuery`/`LayoutBuilder` to adapt at 720px, or is it fixed? Does it reuse shared components and theme tokens (`lib/theme/`), or hardcode colors/spacing? Are loading/empty/error states present?
3. **Cross-feature consistency:** compare against sibling features. If messaging uses a particular context-menu or dialog pattern, the swept feature should too. `grep` for the shared widget to see how others use it.
4. **Reference benchmarks** (read, don't copy):
   - `../daccord` — the Godot reference client. Its scenes/scripts show the intended Daccord UX for this feature. Parity gaps here are findings.
   - Discord/Slack/Telegram behaviour from your own knowledge for this feature's interactions.
5. Produce a *provisional* findings list from code alone, each tagged `[desktop]`, `[mobile]`, or `[both]` and with a severity guess.

## Phase 2 — Live confirmation

Now see it actually render and behave, to confirm/kill provisional findings and catch what code review can't (real layout, overflow, contrast, motion, tap-ability).

**Launch:** prefer the `run` skill, or run on web for browser-driven inspection:
```bash
flutter run -d chrome --web-port 8080   # or the project's usual run path
```
If a daccord MCP server is connected (`mcp__daccord__*`), use it to drive navigation deterministically: `select_space`, `select_channel`, `open_settings`, `open_dm`, `open_thread`, `open_voice_view`, `toggle_member_list`, `toggle_search`, `set_theme`, and `get_current_state` to read where you are. These are faster and more reliable than clicking.

**Capture both viewports** for every relevant surface using the browser tools (`firefox_set_viewport` + `firefox_screenshot`, or equivalent):
- **Mobile:** 390×844 (below the 720px breakpoint — exercises drawers, sheets, gestures).
- **Desktop:** 1440×900 (above it — exercises multi-pane, hover, right-click).

For each surface, walk the primary flow on both viewports. Check the things code can't show you:
- Overflow, clipping, truncation, misalignment, cramped/empty spacing at real sizes.
- Text contrast against the actual theme; test at least one dark and one light theme via `set_theme`.
- Hover/press/focus on desktop; tap-target size and long-press/swipe on mobile.
- Transitions and motion (and that they respect reduce-motion if applicable).
- Empty, loading, and error states triggered live where reachable.

Reconcile: drop provisional findings the live app disproves, upgrade ones that look worse in person, add newly-seen issues. Attach a screenshot to any visual finding.

## Output — the report

A single markdown report. No code changes unless the user asks (then keep them minimal and reuse-first per the repo conventions).

```
# UX Sweep — <feature>

**Scope:** <screens/flows covered>  ·  **Viewports:** mobile 390×844, desktop 1440×900  ·  **Themes:** <which>

## Findings  (ranked, highest impact first)

### 1. <short title>  ·  [both|desktop|mobile]  ·  Severity: High|Medium|Low
- **Lens:** Simplicity | Consistency | Convention
- **What:** what's wrong, where (file:line and/or screenshot)
- **Why it matters:** user impact
- **Benchmark:** how Discord/other apps (or ../daccord) handle it
- **Fix:** the specific, minimal change — reuse an existing component/pattern where possible

### 2. ...

## What's already good
<brief — patterns worth preserving / replicating to other features>

## Out of scope / follow-ups
<anything noticed outside this feature>
```

Ranking rule: order by user impact × frequency. A friction point on the feature's primary flow outranks a cosmetic gap on a rare screen. Be specific and honest — cite real evidence, don't pad the list, and say plainly when a surface is already solid.
