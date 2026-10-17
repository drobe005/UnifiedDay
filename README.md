# UnifiedDay Starter Pack

Working title for the iOS app in `unified-day-mvp-spec.md` (v0.2). EventKit-based,
no backend. This pack is built to be finished in Claude Code.

## What is here

- `Sources/` - SwiftUI scaffold for the v0.1 MVP. Drop these files into an Xcode project.
- `BUILD_PLAN.md` - phased build plan with acceptance criteria. Feed phases to Claude Code one at a time.
- `CLAUDE.md` - project conventions. Put this at the repo root so Claude Code picks it up.
- The full product spec lives at `~/workspace/your_files/unified-day-mvp-spec.md`.

## Setup in Xcode (5 minutes)

1. Xcode > New Project > iOS > App. Name it `UnifiedDay`, interface SwiftUI, language Swift.
   Minimum deployment: iOS 18.0. No Core Data, no tests for now.
2. Drag the `Sources` folder into the project navigator. Check "Copy items if needed"
   and add to the UnifiedDay target. Delete the template `ContentView.swift` and
   `UnifiedDayApp.swift` that Xcode generated (the scaffold has its own app entry).
3. Add usage descriptions. In the target's Info tab, add:
   - `NSCalendarsUsageDescription`: "UnifiedDay shows your calendar events in a single daily timeline."
   - `NSRemindersUsageDescription`: "UnifiedDay shows your reminders next to your events in a single daily timeline."
4. Run on your iPhone (EventKit data in the Simulator is thin). Sign the app with
   your Apple Developer Program team for TestFlight later.

## What works out of the box

- Today timeline: events and reminders due today, overdue pinned, sorted per spec.
- Reminders tab grouped by list, with search.
- Composer sheet for quick add (event or reminder).
- Complete and delete with swipe or tap. Settings shows access state and v0.2 placeholders.

## What Claude Code still needs to build

See `BUILD_PLAN.md`. In short: detail/edit screen, reschedule gesture, search for
events (not just reminders), widget, then the v0.2 integrations (Meet/Zoom,
Notion, Drive).
