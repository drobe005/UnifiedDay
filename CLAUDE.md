# CLAUDE.md - UnifiedDay

## Project

UnifiedDay is an iOS app (SwiftUI, Swift 6, iOS 18+) that shows Apple Calendar
events and Apple Reminders in one daily timeline. EventKit is the source of truth.
There is no backend and no local database in v0.1.

## Conventions

- Swift 6 strict concurrency. `@Observable` for services, `@Environment` for
  injection, `MainActor` for anything touching UI state.
- Keep `EventKitService` as the only type that talks to `EKEventStore`. Views
  never touch EventKit directly.
- `TimelineItem` is the single model for rows. Extend it; do not create parallel
  event/reminder view models.
- Sorting lives in `EventKitService.sortItems` and follows the spec: overdue,
  timed, all-day, due today without time. Do not re-sort in views.
- User-facing copy: plain language, no em dashes, no corporate fluff. One short
  sentence per permission or empty state.
- Errors surface as a non-blocking banner or inline message, never a crash and
  never a silent failure. `lastError` on the service is the channel.

## Workflow

- Work in small phases from BUILD_PLAN.md. Finish one phase fully, including a
  device run, before starting the next.
- Always run on a real iPhone before calling a phase done. The Simulator's
  EventKit data is not representative.
- When touching permissions or Info.plist keys, say so explicitly in the summary.
- Do not add dependencies (SPM packages, SDKs) without asking first. v0.1 is
  dependency-free by design. v0.2 integrations are the exception and get their
  own phases.
- If an EventKit behavior is uncertain, verify against Apple's docs or a device
  test. Do not guess at predicate semantics.
