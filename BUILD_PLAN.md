# UnifiedDay Build Plan

Phases for Claude Code. Do one phase at a time. Each phase is done only when its
acceptance criteria pass on a real iPhone. The product spec is the authority;
this plan is the order of work.

## Phase 0 - Project setup (done 2026-10-17, verified on iPhone 16 Pro Max)

- Xcode iOS app project `UnifiedDay`, iOS 18+, SwiftUI, no Core Data.
- `Sources/` files added to target, template files removed.
- `NSCalendarsUsageDescription` and `NSRemindersUsageDescription` set.
- App launches, onboarding requests access, Today shows real data.

Acceptance: on device, grant access, see today's real events and reminders.

## Phase 1 - Detail and edit (done 2026-10-17, verified on iPhone 16 Pro Max)

- Tap a timeline row opens a detail sheet: title, date/time, source calendar/list,
  notes, delete.
- Editable fields save back through `EventKitService`. Read-only items (shared
  calendars) hide edit controls.
- Add `updateEvent` and `updateReminder` to the service.

Acceptance: edit a title and time in the app, see the change in Apple Calendar
or Reminders within 5 seconds, and vice versa.

## Phase 2 - Reschedule gestures (done 2026-10-17, verified on iPhone 16 Pro Max; drag-to-time deferred)

- Swipe a reminder row: "Tomorrow" and "Next week" actions.
- Optional: drag a reminder onto a time in the Today view (time-blocking).
- Overdue behavior per the decided rule (pinned until acted on, or auto-roll).

Acceptance: reschedule from the app, verify in Apple Reminders.

## Phase 3 - Search and polish (done 2026-10-31, verified on iPhone 16 Pro Max)

- Search across events and reminders for the next 30 days (reminders search
  exists; extend to events).
- Empty, loading, and denied-permission states reviewed on device.
- App icon badge count setting wired up.
- Accessibility pass: labels on all buttons, Dynamic Type sanity.

Acceptance: the v0.1 success metrics in the spec (sub-second Today view,
10-second quick add, zero sync surprises).

## Phase 4 - TestFlight

- App icon, launch screen, version number.
- Archive, upload to App Store Connect, TestFlight internal build.
- Install on the daily iPhone and use for a week before calling v0.1 done.

Acceptance: daily use for 7 days with no data loss or sync surprises.

## Phase 5 - v0.2 integrations (in build order, TBD)

1. Notion: OAuth, database picker, property mapping, poll-based two-way sync.
2. Google Drive: file picker, attachments row, shared Google sign-in.
3. Video meetings: Google Meet via Calendar API conference data, Zoom via API.
   Needs a Zoom OAuth app registered in the Zoom marketplace.

Each integration gets its own sub-phase with the same rule: device-tested
before done. Integrations stay additive; the timeline works with none
connected.

## Phase 6 - Redesign (branch `redesign`, in progress)

Rebuild the look to match the Figma page "Redesign (Untitled UI)" in the Unified Day
file. Colors come from the app icon and live in `Assets.xcassets/Colors`, each with
a light and dark version, named like the "UnifiedDay" styles in Figma. Shared pieces
live in `Sources/DesignSystem`. Decisions: keep San Francisco (no Inter), keep
Apple's tab bar, navigation and sheets (tinted), derive dark mode colors.

1. Foundation: color sets, `UD` tokens, shared components, brand tint, Settings.
   (done 2026-11-12, checked in the Simulator in light and dark)
2. Today and Calendar: timeline cards, section headers, summary badges.
   (done 2026-11-12, checked in the Simulator in light and dark)
3. Reminders and Needs Attention.
   (done 2026-11-12, checked in the Simulator in light and dark)
4. Notes: list, folders, editor.
   (done 2026-11-12, checked in the Simulator in light and dark)
5. Composer sheets, item detail, onboarding, access and empty states, Tab Order.
   (done 2026-11-12, checked in the Simulator in light and dark. The error banner
   and the Move sheet were restyled but not seen on screen.)

Acceptance per step: matches the Figma screen in light mode, reads well in dark
mode, Dynamic Type still works, and nothing behaves differently. Run on a real
iPhone before merging to `main`.
