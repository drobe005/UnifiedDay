# UnifiedDay

Working title for an iOS app that shows Apple Calendar events and Reminders in one
daily timeline. EventKit-based, no backend. Built in Claude Code.

Want early access? Join the TestFlight beta waitlist: https://deiondrickroberts.com/unifiedday-beta?ref=github

## What is here

- `UnifiedDay.xcodeproj` - the Xcode project.
- `Sources/` - the SwiftUI app.
- `BUILD_PLAN.md` - phased build plan with acceptance criteria. Feed phases to Claude Code one at a time.
- `docs/waitlist.md` - how the beta waitlist works.
- `CLAUDE.md` - project conventions. Put this at the repo root so Claude Code picks it up.
- The full product spec is attached to the UnifiedDay page in Notion.

## Run it

Open `UnifiedDay.xcodeproj` in Xcode (iOS 18+, Swift 6). The target picks up every
file in `Sources/` automatically. Signing uses Automatic with team S77K343D39.
Run on a real iPhone: EventKit data in the Simulator is thin.

## Status

See `BUILD_PLAN.md` for phases and the UnifiedDay page in Notion for the build log.
